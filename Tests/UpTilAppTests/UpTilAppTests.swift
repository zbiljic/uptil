import Testing
@testable import UpTil

@Suite("UpTil application")
struct UpTilAppTests {
    @Test("uses the registered bundle identifier")
    func bundleIdentifier() {
        #expect(AppMetadata.bundleIdentifier == "com.zbiljic.uptil")
    }
}
