import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = SessionController()
    private lazy var controlServer = MCPControlServer(handler: MCPCommandHandler(controller: controller))

    func applicationDidFinishLaunching(_: Notification) {
        guard Self.shouldStartControlServer(environment: ProcessInfo.processInfo.environment) else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemClockDidChange),
            name: .NSSystemClockDidChange,
            object: nil
        )
        controlServer.start()
    }

    func applicationWillTerminate(_: Notification) {
        tearDownControlSurface()
    }

    private func tearDownControlSurface() {
        controlServer.stop()
        NotificationCenter.default.removeObserver(self, name: .NSSystemClockDidChange, object: nil)
        controller.shutdown()
    }

    @objc
    nonisolated private func systemClockDidChange(_: Notification) {
        Task { @MainActor [weak self] in
            self?.controller.reconcileClockChange()
        }
    }

    static func shouldStartControlServer(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
    }
}
