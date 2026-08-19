import AppKit
import SwiftUI

@main
struct UpTilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            SessionPopover(controller: appDelegate.controller)
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}
