#if os(macOS)
import SwiftUI
import AppKit

/// M16.8: hosts the screen-anchored tile wall in an `NSHostingView` whose
/// frame is positioned at the AppKit level — no SwiftUI state writes, no
/// body re-evaluation, no layout passes. The compositor simply translates
/// an already-rendered layer tree.
///
/// M17.2 (full B): during a move/resize the anchoring is driven by a
/// `CADisplayLink` that polls `window.frame` once per vsync. The original
/// notification-only chain (didMove → main queue → reposition) corrected
/// the wall at mouse-event rate and coalesced under load, so the wall
/// visibly chased the window in hops; vsync polling makes the correction
/// land every frame, at most one frame behind WindowServer's own move
/// compositing. The link starts on the first move/resize notification
/// and stops itself after ~0.2 s without frame changes; outside drags
/// the notification path alone keeps the wall anchored.
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
            if window == nil {
                // CADisplayLink retains its target — drop it when the
                // view leaves the window.
                stopFollowing()
            }
            attach(to: window)
            reposition()
            #if DEBUG
            maybeStartDragDriver()
            #endif
        }

        #if DEBUG
        // MARK: - Debug self-drag driver (perf harness, no AX needed)

        /// `REBORN_ZUNE_DEBUG_DRAG=<amplitude-pt>`: after a 4 s settle,
        /// moves the window in a Lissajous pattern (ramping up to
        /// `amplitude` pt over 6 s, holding 6 s), exercising the exact
        /// didMove → reposition path a manual drag does. Pair with CPU
        /// sampling of the app and WindowServer.
        private var dragDriver: CADisplayLink?
        private var dragStart: TimeInterval = 0
        private var dragHome: NSPoint = .zero
        private var dragAmplitude: Double = 0

        private func maybeStartDragDriver() {
            guard dragDriver == nil, let window,
                  let raw = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_DRAG"],
                  let amp = Double(raw), amp > 0 else { return }
            dragHome = window.frame.origin
            dragAmplitude = amp
            dragStart = Date.timeIntervalSinceReferenceDate + 4
            guard let link = (window.screen ?? NSScreen.main)?
                .displayLink(target: self, selector: #selector(dragFire(_:))) else { return }
            link.add(to: .main, forMode: .common)
            dragDriver = link
        }

        @objc private nonisolated func dragFire(_ link: CADisplayLink) {
            MainActor.assumeIsolated {
                let t = Date.timeIntervalSinceReferenceDate - dragStart
                guard t < 12 else {
                    dragDriver?.invalidate()
                    dragDriver = nil
                    return
                }
                guard t >= 0 else { return }
                let ramp = dragAmplitude * min(1, t / 6)
                let dx = ramp * sin(t * 2 * .pi * 0.7)
                let dy = ramp * 0.6 * sin(t * 2 * .pi * 1.13)
                let t0 = CACurrentMediaTime()
                window?.setFrameOrigin(NSPoint(x: dragHome.x + dx, y: dragHome.y + dy))
                // Harness telemetry: fire rate + how long setFrameOrigin
                // itself blocks the main thread (WindowServer IPC).
                dragFires += 1
                dragSetMs += (CACurrentMediaTime() - t0) * 1000
                if t - dragLastReport >= 1 {
                    FileHandle.standardError.write(
                        "[drag] fires \(dragFires)/s, setFrameOrigin avg \(dragSetMs / Double(max(1, dragFires))) ms\n"
                            .data(using: .utf8)!)
                    dragFires = 0
                    dragSetMs = 0
                    dragLastReport = t
                }
            }
        }

        private var dragFires = 0
        private var dragSetMs: Double = 0
        private var dragLastReport: TimeInterval = 0
        #endif

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
            // willMove covers drags started from the invisible title-bar
            // strip (also a WindowServer session — no didMove until
            // drop, so the follow link must start here).
            observers.append(center.addObserver(
                forName: NSWindow.willMoveNotification, object: newWindow, queue: nil
            ) { [weak self] _ in
                guard Thread.isMainThread else { return }
                MainActor.assumeIsolated { self?.beginFollowing() }
            })
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                // queue: nil — run the block SYNCHRONOUSLY on the posting
                // thread. Window move/resize notifications post on the
                // main thread from inside the same run-loop iteration
                // that commits the window's new frame, so a synchronous
                // correction lands in the SAME CA commit as the move: the
                // wall never appears at a stale offset. Any async hop
                // (queue: .main, Task) defers the correction to a later
                // commit, leaving a 1-frame rubber band whose size grows
                // with drag speed — the visible drag judder.
                observers.append(center.addObserver(
                    forName: name, object: newWindow, queue: nil
                ) { [weak self] _ in
                    guard Thread.isMainThread else {
                        Task { @MainActor [weak self] in self?.reposition() }
                        return
                    }
                    MainActor.assumeIsolated {
                        self?.reposition()
                        // M17.2 (full B): a move/resize means a drag is
                        // likely underway — switch to vsync-driven
                        // following as a backstop for the remainder.
                        self?.beginFollowing()
                    }
                })
            }
        }

        // MARK: - Window drag via WindowServer session (M17.2)

        /// `isMovableByWindowBackground` drags the window on the legacy
        /// AppKit path — every mouse event round-trips through the app's
        /// main thread, which capped effective motion at ~20 fps under
        /// load (measured). `performDrag(with:)` starts the modern
        /// WindowServer-managed session instead: WindowServer drives the
        /// move itself at full display rate (how Finder windows drag),
        /// while the drag-anywhere UX is preserved.
        override public var mouseDownCanMoveWindow: Bool { false }

        override public func mouseDown(with event: NSEvent) {
            // A WindowServer drag session posts NO didMove notifications
            // (measured: the follow link never started), so kick it off
            // here — we know a drag is beginning.
            beginFollowing()
            window?.performDrag(with: event)
        }

        // MARK: - Vsync following during drags (M17.2)

        /// Polls `window.frame` once per vsync while a drag is underway.
        private var followLink: CADisplayLink?
        /// Last time a poll actually moved the wall; the link stops
        /// itself once the window has been still for this long.
        private var lastFollowMove: TimeInterval = 0

        private func beginFollowing() {
            guard followLink == nil else { return }
            guard let screen = window?.screen ?? NSScreen.main else { return }
            lastFollowMove = Date.timeIntervalSinceReferenceDate
            let link = screen.displayLink(target: self, selector: #selector(followFire(_:)))
            // The wall trail behind a dragged window is velocity × one
            // frame — ask ProMotion for the full 120 Hz so the trail is
            // 8 ms, not 16. Without this the link was observed firing
            // at 60–88 Hz during drags.
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60, maximum: 120, preferred: 120
            )
            // .common so it keeps firing inside the event-tracking run
            // loop of a live title-bar/edge drag.
            link.add(to: .main, forMode: .common)
            followLink = link
        }

        private func stopFollowing() {
            followLink?.invalidate()
            followLink = nil
        }

        /// CADisplayLink fires on the run loop it was added to (`.main`).
        @objc private nonisolated func followFire(_ link: CADisplayLink) {
            MainActor.assumeIsolated {
                let before = hostingView?.frame
                // During a WindowServer drag session the AppKit frame
                // updates sparsely (~15–20 Hz measured from real drags):
                // corrections issued from it snap the wall in visible
                // hops. CGWindow bounds are the compositor's live truth.
                // No velocity prediction here: at low speed its estimate
                // noise vibrates the wall, at high speed it overshoots —
                // the plain 1-frame trail at 120 Hz reads far better.
                if let screen = window?.screen ?? NSScreen.main,
                   let tl = liveTopLeft(screen: screen) {
                    reposition(topLeft: tl)
                } else {
                    reposition()
                }
                #if DEBUG
                dragStatsTick(corrected: hostingView?.frame != before)
                #endif
                if hostingView?.frame != before {
                    lastFollowMove = Date.timeIntervalSinceReferenceDate
                } else if Date.timeIntervalSinceReferenceDate - lastFollowMove > 0.2 {
                    // Drag over (or never began — e.g. a programmatic
                    // move). ~0.2 s mirrors the WindowActivityMonitor
                    // watchdog tail.
                    stopFollowing()
                }
            }
        }

        #if DEBUG
        /// REBORN_ZUNE_DEBUG_DRAG_STATS=1: corrections/s during drags.
        private var statStart: TimeInterval = 0
        private var statFires = 0
        private var statCorrections = 0

        private func dragStatsTick(corrected: Bool) {
            guard ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_DRAG_STATS"] == "1" else { return }
            let now = Date.timeIntervalSinceReferenceDate
            if statStart == 0 { statStart = now }
            statFires += 1
            if corrected { statCorrections += 1 }
            if now - statStart >= 1 {
                FileHandle.standardError.write(
                    "[follow] fires \(statFires)/s, corrections \(statCorrections)/s\n".data(using: .utf8)!)
                statStart = now
                statFires = 0
                statCorrections = 0
            }
        }
        #endif

        /// The window's top-left in screen-local points (y DOWN) read
        /// from WindowServer via CGWindowList — live even mid-drag-
        /// session, unlike `NSWindow.frame`. Bounds of one's own window
        /// need no screen-recording permission.
        private func liveTopLeft(screen: NSScreen) -> CGPoint? {
            guard let window else { return nil }
            let wid = CGWindowID(window.windowNumber)
            guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [NSDictionary],
                  let info = list.first,
                  let raw = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary)
            else { return nil }
            // CGWindow bounds: global Quartz, y DOWN from the primary
            // display's top. Convert to the AppKit top (y UP) first.
            let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let appKitTop = primaryH - bounds.minY
            return CGPoint(
                x: bounds.minX - screen.frame.minX,
                y: screen.frame.maxY - appKitTop
            )
        }

        /// Pins the wall to the hardware screen: the wall's top-left stays
        /// at screen-local (0, 0) no matter where the window goes, so the
        /// window is just a viewport sliding over a fixed wall.
        private func reposition() {
            guard let window else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }
            // Window top-left in screen-local points, y DOWN (same
            // convention M16.3 used).
            let tl = CGPoint(
                x: window.frame.minX - screen.frame.minX,
                y: screen.frame.maxY - window.frame.maxY
            )
            reposition(topLeft: tl)
        }

        private func reposition(topLeft tl: CGPoint) {
            guard let window, let hostingView else { return }
            #if DEBUG
            // REBORN_ZUNE_DEBUG_NO_ANCHOR=1: freeze the wall anchor
            // entirely — A/B baseline for drag-compositing cost.
            if ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_ANCHOR"] == "1" { return }
            #endif
            guard let screen = window.screen ?? NSScreen.main else { return }
            // Desired wall origin (bottom-left, y UP) in window base
            // coordinates: content top plus the y-down offset, minus the
            // wall height.
            let contentTop = window.contentLayoutRect.maxY
            let inWindow = NSPoint(
                x: -tl.x,
                y: contentTop + tl.y - wallSize.height
            )
            var newFrame = NSRect(
                origin: convert(inWindow, from: nil),
                size: wallSize
            )
            // M17.2: snap the in-window origin to the device-pixel grid.
            // A fractional offset resamples the wall texture into the
            // window surface with a phase that drifts as the window
            // moves; combined with the window's own fractional on-screen
            // resampling that double resampling reads as a fine
            // vibration. Pixel-snapping keeps the wall 1:1 inside the
            // window (≤0.25 pt anchor error, invisible) — what remains
            // is the single uniform resampling every window gets.
            let px = 1.0 / (window.backingScaleFactor > 0 ? window.backingScaleFactor : 2)
            newFrame.origin.x = (newFrame.origin.x / px).rounded() * px
            newFrame.origin.y = (newFrame.origin.y / px).rounded() * px
            // M17.1: only REAL wall movement counts as window activity.
            // SwiftUI layout passes (playback clock, other timelines)
            // trigger layout() → reposition() constantly; counting those
            // latched WindowActivityMonitor.isActive to true forever,
            // freezing the wall clock and lighting permanently.
            guard newFrame != hostingView.frame else { return }
            WindowActivityMonitor.shared.noteActivity()
            hostingView.frame = newFrame
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
///
/// M17.2: the monitor also tracks suspension time so `WallTime` can
/// subtract it — rendering freezes during a drag, and now the wall's
/// animation clock freezes with it instead of jumping forward on resume.
@MainActor
@Observable
public final class WindowActivityMonitor {
    public static let shared = WindowActivityMonitor()

    public private(set) var isActive = false
    private var lastActivity: TimeInterval = 0
    private var watchdog: Task<Void, Never>?

    /// Wall-clock moment the current suspension began (rising edge only).
    private var suspendedAt: TimeInterval?
    /// Total wall-clock time spent suspended across all past drags.
    public private(set) var suspendedTotal: TimeInterval = 0

    private init() {}

    /// The wall's animation time: wall clock minus every suspended
    /// interval, held constant while a suspension is in flight. On resume
    /// it continues from exactly where it froze — no forward jump.
    public var wallNow: TimeInterval {
        let raw = Date.timeIntervalSinceReferenceDate
        return (suspendedAt ?? raw) - suspendedTotal
    }

    public func noteActivity() {
        if !isActive {
            suspendedAt = Date.timeIntervalSinceReferenceDate
        }
        isActive = true
        lastActivity = Date.timeIntervalSinceReferenceDate
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled else { return }
                if Date.timeIntervalSinceReferenceDate - self.lastActivity >= 0.25 {
                    if let began = self.suspendedAt {
                        self.suspendedTotal += Date.timeIntervalSinceReferenceDate - began
                        self.suspendedAt = nil
                    }
                    self.isActive = false
                    self.watchdog = nil
                    return
                }
            }
        }
    }
}
#endif
