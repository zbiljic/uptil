import Foundation
import Testing
@testable import UpTilCore

@Suite("Control socket path")
struct ControlSocketPathTests {
    @Test("derives the app-container endpoint")
    func endpoint() {
        let home = URL(filePath: "/Users/test")
        let path = ControlSocketPath.socketURL(home: home, runningInsideContainer: false)
        #expect(path?.path == "/Users/test/Library/Containers/com.zbiljic.uptil/Data/tmp/uptil.sock")
        let containerPath = ControlSocketPath.socketURL(
            home: URL(filePath: "/Users/test/Library/Containers/com.zbiljic.uptil/Data"),
            runningInsideContainer: true
        )
        #expect(containerPath?.path.hasSuffix("/Data/tmp/uptil.sock") == true)
    }

    @Test("rejects paths beyond sockaddr_un capacity")
    func lengthBoundary() {
        let suffixByteCount = "/tmp/uptil.sock".utf8.count
        let maximumHomeBytes = ControlSocketPath.maximumPathBytes - suffixByteCount - 1
        let exactHome = URL(filePath: "/" + String(repeating: "a", count: maximumHomeBytes - 1))
        let oversizedHome = URL(filePath: "/" + String(repeating: "a", count: maximumHomeBytes))
        #expect(ControlSocketPath.socketURL(home: exactHome, runningInsideContainer: true) != nil)
        #expect(ControlSocketPath.socketURL(home: oversizedHome, runningInsideContainer: true) == nil)
    }
}
