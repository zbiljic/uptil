import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = SessionController()

    func applicationWillTerminate(_: Notification) {
        controller.shutdown()
    }
}
