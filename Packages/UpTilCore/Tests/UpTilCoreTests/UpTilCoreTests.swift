import Testing
@testable import UpTilCore

@Suite("UpTilCore")
struct UpTilCoreTests {
    @Test("exposes the application bundle identifier")
    func appBundleIdentifier() {
        #expect(UpTilCore.appBundleIdentifier == "com.zbiljic.uptil")
    }
}
