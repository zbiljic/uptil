import Testing
@testable import UpTil

@Suite("UpTil application")
struct UpTilAppTests {
    @Test("uses the registered bundle identifier")
    func bundleIdentifier() {
        #expect(AppMetadata.bundleIdentifier == "com.zbiljic.uptil")
    }

    @Test("control server starts normally but not in the XCTest host")
    func controlServerLaunchGuard() {
        #expect(AppDelegate.shouldStartControlServer(environment: [:]))
        #expect(!AppDelegate.shouldStartControlServer(environment: [
            "XCTestConfigurationFilePath": "/tmp/UpTilTests.xctestconfiguration",
        ]))
    }
}
