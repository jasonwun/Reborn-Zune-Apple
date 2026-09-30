#if os(macOS)
import SwiftUI
import AppKit

/// M16.8: hosts the screen-anchored tile wall in an `NSHostingView` whose
/// frame is positioned DIRECTLY in response to window move/resize
/// notifications — no SwiftUI state writes, no body re-evaluation, no
/// layout passes. The compositor simply translates an already-rendered
/// layer tree, so the wall tracks the window at full display rate even
/// during manual title-bar drags and top/left-edge resize drags.
///
/// Replaces the M16.3/M16.7 chain (`WindowOriginReporter` → `@State` →
/// `resonantWindowOrigin` → `.offset(-origin)`), which pushed every window
/// movement through SwiftUI's update loop: at mouse-event rate each write
/// re-evaluated the whole ~965-tile subtree and re-rendered the Metal
/// shader layers, so the wall's internal frame rate collapsed during
/// manual drags even after 60 Hz throttling.
///
/// The container itself is laid out by SwiftUI (fills the Now Playing
/// background slot, `.ignoresSafeArea()`); only the wall's position inside
/// it is managed at the AppKit level.
public struct ScreenAnchorContainer<Content: View>: NSViewRepresentable {
    /// Frozen wall size (screen + one-large-tile margin, per
    /// `TileWallView.frozenPanelSize`). Captured once at `makeNSView` —
    /// later body re-evaluations carrying a new value are ignored,
    /// matching the wall's freeze-on-entry semantics (M16.1).
    let wallSize: CGSize
    /// Hardware screen size, re-injected into the hosted hierarchy —
    /// an `NSHostingView` starts a fresh environment root, and the wall
    /// reads `resonantScreenSize` for its freeze + light-field size.
    let screenSize: CGSize?
    let content: Content

    public init(
        wallSize: CGSize,
        screenSize: CGSize?,
        @ViewBuilder content: () -> Content
    ) {
        self.wallSize = wallSize
        self.screenSize = screenSize
        self.content = content()
    }

    public func makeNSView(context: Context) -> AnchorNSView {
        let container = AnchorNSView(wallSize: wallSize)
        container.install(rootView: AnyView(
            content.environment(\.resonantScreenSize, screenSize)
        ))
        return container
    }

    public func updateNSView(_ container: AnchorNSView, context: Context) {
        // Propagate content changes (e.g. the real library replacing the
        // demo tiles). The frozen wall size is deliberately NOT updated —
        // a resize must never re-flow the arrangement (M16.1).
        container.update(rootView: AnyView(
            content.environment(\.resonantScreenSize, screenSize)
        ))
    }

    // MARK: - The AppKit container view

    /// Plain NSView that owns the hosting view and repositions it whenever
    /// the window moves or resizes. All math happens in the window's base
    /// coordinate system; `convert(_:from: nil)` bridges into view-local
    /// coordinates, so the container does not have to assume it exactly
    /// fills the window's content area.
    @MainActor
    public final class AnchorNSView: NSView {
        private let wallSize: CGSize
        private var hostingView: NSHostingView<AnyView>?
        private var observers: [NSObjectProtocol] = []
        private var observedWindow: NSWindow?

        init(wallSize: CGSize) {
            self.wallSize = wallSize
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = true
            autoresizesSubviews = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func install(rootView: AnyView) {
            let hosting = NSHostingView(rootView: rootView)
            hosting.sizingOptions = []
            hosting.autoresizingMask = []
            // Kill the bridged titlebar safe-area inset: the window uses
            // fullSizeContentView with a transparent hidden titlebar, and
            // the wall must paint through that strip — otherwise the top
            // ~31pt of the window shows the wall's bare grey backdrop
            // with no tiles and no lighting (the "bright/dark band").
            hosting.safeAreaRegions = []
            hosting.frame = NSRect(origin: .zero, size: wallSize)
            addSubview(hosting)
            hostingView = hosting
            reposition()
        }

        func update(rootView: AnyView) {
            guard let hostingView else { return }
            hostingView.rootView = rootView
        }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach(to: window)
            reposition()
        }

        override public func layout() {
            super.layout()
            // The container's own frame is driven by SwiftUI; when it
            // changes during a resize drag the wall must be re-anchored
            // against the NEW window geometry as well.
            reposition()
        }

        private func attach(to newWindow: NSWindow?) {
            guard newWindow !== observedWindow else { return }
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            observedWindow = newWindow
            guard let newWindow else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(center.addObserver(
                    forName: name, object: newWindow, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.reposition() }
                })
            }
        }

        /// Pins the wall to the hardware screen: the wall's top-left stays
        /// at screen-local (0, 0) no matter where the window goes, so the
        /// window is just a viewport sliding over a fixed wall.
        private func reposition() {
            guard let window, let hostingView else { return }
            WindowActivityMonitor.shared.noteActivity()
            guard let screen = window.screen ?? NSScreen.main else { return }
            // Window top-left in screen-local points, y DOWN (same
            // convention M16.3 used).
            let tl = CGPoint(
                x: window.frame.minX - screen.frame.minX,
                y: screen.frame.maxY - window.frame.maxY
            )
            // Desired wall origin (bottom-left, y UP) in window base
            // coordinates: content top plus the y-down offset, minus the
            // wall height.
            let contentTop = window.contentLayoutRect.maxY
            let inWindow = NSPoint(
                x: -tl.x,
                y: contentTop + tl.y - wallSize.height
            )
            hostingView.frame = NSRect(
                origin: convert(inWindow, from: nil),
                size: wallSize
            )
        }
    }
}

// MARK: - Wall viewport probe (flip pool)

/// M16.10: the app's main visible window expressed in WALL coordinates
/// (screen-local, y-down, origin at the screen's top-left). The wall is
/// screen-anchored, so this rect is exactly the slice of the wall the
/// window reveals. Read on demand by the flip coordinator at each tick
/// (every 5 s) — never observed by SwiftUI, so window movement keeps
/// zero presence in the update loop.
@MainActor
enum WallViewport {
    static func current() -> CGRect? {
        // The app briefly owns a phantom 0×0 helper window; pick the
        // largest real visible window instead of assuming windows[0].
        let window = NSApp.windows
            .filter { $0.isVisible && $0.frame.width > 100 && $0.frame.height > 100 }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        guard let window, let screen = window.screen ?? NSScreen.main else { return nil }
        return CGRect(
            x: window.frame.minX - screen.frame.minX,
            y: screen.frame.maxY - window.frame.maxY,
            width: window.frame.width,
            height: window.frame.height
        )
    }
}

// MARK: - Window activity monitor (drag/resume lighting suspension)

/// M16.9: true while the window is being dragged or resized (driven by
/// `ScreenAnchorContainer.AnchorNSView` reposition events, cleared 250 ms
/// after the last one). `LightingModifier` pauses its TimelineView while
/// active: during a drag the screen-anchored wall is static relative to
/// the screen anyway, so freezing the light frame is visually correct —
/// and stopping the 15 fps full-wall Metal re-render frees the GPU and
/// WindowServer for move compositing (idle WindowServer CPU was measured
/// at ~48% from the constant re-render alone).
@MainActor
@Observable
public final class WindowActivityMonitor {
    public static let shared = WindowActivityMonitor()

    public private(set) var isActive = false
    private var lastActivity: TimeInterval = 0
    private var watchdog: Task<Void, Never>?

    private init() {}

    public func noteActivity() {
        isActive = true
        lastActivity = Date.timeIntervalSinceReferenceDate
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled else { return }
                if Date.timeIntervalSinceReferenceDate - self.lastActivity >= 0.25 {
                    self.isActive = false
                    self.watchdog = nil
                    return
                }
            }
        }
    }
}
#endif
