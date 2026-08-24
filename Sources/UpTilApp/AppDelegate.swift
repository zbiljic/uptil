import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = SessionController()
    private lazy var controlServer = MCPControlServer(handler: MCPCommandHandler(controller: controller))

    func applicationDidFinishLaunching(_: Notification) {
        guard Self.shouldStartControlServer(environment: ProcessInfo.processInfo.environment) else { return }
        controlServer.start()
    }

    func applicationWillTerminate(_: Notification) {
        tearDownControlSurface()
    }

    private func tearDownControlSurface() {
        controlServer.stop()
        controller.shutdown()
    }

    static func shouldStartControlServer(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
    }
}
