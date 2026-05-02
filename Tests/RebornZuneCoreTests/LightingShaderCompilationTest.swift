import XCTest
#if canImport(Metal)
import Metal
#endif
@testable import RebornZuneCore

final class LightingShaderCompilationTest: XCTestCase {
    func testZuneLightingFunctionExistsInModuleMetalLibrary() throws {
        #if canImport(Metal)
        let device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device available on this host.")
        guard let device else { return }

        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .module)
        } catch {
            XCTFail("Could not load module Metal library: \(error)")
            return
        }

        let names = library.functionNames
        XCTAssertTrue(
            names.contains("zuneLighting"),
            "Expected 'zuneLighting' in module metallib; found: \(names)"
        )
        XCTAssertNotNil(
            library.makeFunction(name: "zuneLighting"),
            "Could not instantiate MTLFunction for zuneLighting."
        )
        #else
        throw XCTSkip("Metal is not available on this platform.")
        #endif
    }
}
