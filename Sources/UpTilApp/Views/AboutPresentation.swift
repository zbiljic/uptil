import AppKit
import SwiftUI

/// The footer's info control: a small menu that names the version and links to the project.
/// The version stays out of the footer itself, so the controls there keep their room.
enum AboutPresentation {
    static let systemImage = "info.circle"
    static let help = "About UpTil"
    static let accessibilityLabel = "About UpTil"
    static let accessibilityHint = "Shows the version and links to the project page"

    enum Link: CaseIterable, Hashable {
        case projectPage
        case reportIssue

        var title: String {
            switch self {
            case .projectPage: "Project Page"
            case .reportIssue: "Report an Issue…"
            }
        }

        var url: URL? {
            switch self {
            case .projectPage: AppMetadata.projectPageURL
            case .reportIssue: AppMetadata.issuesURL
            }
        }
    }

    /// The menu's first, inert line; an unversioned build (such as a bare debug run) reads "dev".
    static func versionLabel(version: String? = AppMetadata.version()) -> String {
        "UpTil \(version ?? "dev")"
    }

    /// The version line, a separator, then one item per link carrying that link as its represented object.
    @MainActor
    static func menu(target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu(title: accessibilityLabel)
        menu.autoenablesItems = false

        let version = NSMenuItem(title: versionLabel(), action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())

        for link in Link.allCases {
            let item = NSMenuItem(title: link.title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = link
            menu.addItem(item)
        }

        return menu
    }

    /// Hands the link's page to `open`; reports whether a page existed to open.
    @discardableResult
    @MainActor
    static func open(_ link: Link, with open: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        guard let url = link.url else { return false }
        return open(url)
    }
}

/// A bare image button that drops the About menu beneath itself. SwiftUI's `Menu` sits on a
/// pop-up button whose minimum width the footer cannot spare without wrapping the toggle label.
struct AboutMenuButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(
            systemSymbolName: AboutPresentation.systemImage,
            accessibilityDescription: AboutPresentation.accessibilityLabel
        ) ?? NSImage()
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.showMenu))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(textStyle: .callout)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = AboutPresentation.help
        button.setAccessibilityLabel(AboutPresentation.accessibilityLabel)
        button.setAccessibilityHelp(AboutPresentation.accessibilityHint)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_: NSButton, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        @objc
        func showMenu(_ sender: NSButton) {
            let menu = AboutPresentation.menu(target: self, action: #selector(openLink))
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
        }

        @objc
        func openLink(_ item: NSMenuItem) {
            guard let link = item.representedObject as? AboutPresentation.Link else { return }
            AboutPresentation.open(link)
        }
    }
}
