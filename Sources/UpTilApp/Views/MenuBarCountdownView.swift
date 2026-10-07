import AppKit
import Foundation
import SwiftUI
import UpTilCore

enum MenuBarActiveLabelContent {
    case countdown(String)
    case indefinite

    var display: String {
        "⟩\(center)⟨"
    }

    fileprivate var center: String {
        switch self {
        case let .countdown(duration):
            duration
        case .indefinite:
            "∞"
        }
    }

    fileprivate var centerFont: NSFont {
        switch self {
        case .countdown:
            NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        case .indefinite:
            NSFont.systemFont(ofSize: 14, weight: .regular)
        }
    }
}

enum MenuBarActiveLabelRenderer {
    private static let frameHeight: CGFloat = 20
    private static let angleFontSize: CGFloat = 18

    static func image(for content: MenuBarActiveLabelContent) -> NSImage {
        let glyph = NSMutableAttributedString(
            string: content.display,
            attributes: [
                .font: NSFont.systemFont(ofSize: angleFontSize, weight: .regular),
                .foregroundColor: NSColor.black,
                .kern: -0.75,
            ]
        )
        glyph.addAttributes(
            [
                .font: content.centerFont,
                .baselineOffset: 1.0,
            ],
            range: NSRange(location: 1, length: content.center.utf16.count)
        )

        let glyphSize = glyph.size()
        let frameSize = NSSize(width: ceil(glyphSize.width), height: frameHeight)
        let drawingPoint = NSPoint(
            x: 0,
            y: (frameSize.height - glyphSize.height) / 2
        )
        let image = NSImage(size: frameSize)
        image.lockFocus()
        glyph.draw(at: drawingPoint)
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = content.display
        return image
    }
}

struct MenuBarCountdownView: View {
    let deadline: Date

    private let now: @MainActor () -> Date
    @State private var calculationDate: Date

    init(deadline: Date, now: @escaping @MainActor () -> Date = { Date() }) {
        self.deadline = deadline
        self.now = now
        _calculationDate = State(initialValue: now())
    }

    var body: some View {
        let remaining = deadline.timeIntervalSince(calculationDate)
        let duration = MenuBarCountdownFormatting.durationString(remaining: remaining)

        Image(nsImage: MenuBarActiveLabelRenderer.image(for: .countdown(duration)))
            .accessibilityLabel("UpTil active, \(duration) remaining")
            .task(id: deadline) {
                await refreshClock()
            }
    }

    private func refreshClock() async {
        calculationDate = now()

        while !Task.isCancelled {
            let currentDate = now()
            let remaining = deadline.timeIntervalSince(currentDate)
            let delay = MenuBarCountdownFormatting.nextRefreshDelay(remaining: remaining)

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            calculationDate = now()
        }
    }
}
