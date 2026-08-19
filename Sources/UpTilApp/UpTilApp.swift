import AppKit
import SwiftUI

@main
struct UpTilApp: App {
    var body: some Scene {
        MenuBarExtra(
            AppMetadata.displayName,
            systemImage: "timer"
        ) {
            Text("UpTil is ready")

            Divider()

            Button("Quit UpTil") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
