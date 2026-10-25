import AppKit
import SwiftUI

/// Reports whether the hosting window is on screen. MenuBarExtra keeps the popover's views
/// alive while it is closed, so appearing and disappearing don't mark each open and close.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onVisibilityChange: @MainActor (Bool) -> Void

    func makeNSView(context _: Context) -> ObservingView {
        ObservingView(onVisibilityChange: onVisibilityChange)
    }

    func updateNSView(_ view: ObservingView, context _: Context) {
        view.onVisibilityChange = onVisibilityChange
    }

    final class ObservingView: NSView {
        var onVisibilityChange: @MainActor (Bool) -> Void
        private var reportedVisibility: Bool?

        init(onVisibilityChange: @escaping @MainActor (Bool) -> Void) {
            self.onVisibilityChange = onVisibilityChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("WindowVisibilityObserver is created only in code")
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didChangeOcclusionStateNotification,
                object: nil
            )
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(occlusionStateDidChange),
                    name: NSWindow.didChangeOcclusionStateNotification,
                    object: window
                )
            }
            reportVisibility()
        }

        @objc
        private func occlusionStateDidChange(_: Notification) {
            reportVisibility()
        }

        private func reportVisibility() {
            let isVisible = window?.occlusionState.contains(.visible) ?? false
            guard isVisible != reportedVisibility else {
                return
            }

            reportedVisibility = isVisible
            // The view can join its window during a SwiftUI update, which must not change state.
            Task { @MainActor [weak self] in
                self?.onVisibilityChange(isVisible)
            }
        }
    }
}
