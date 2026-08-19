import AppKit
import SwiftUI

enum MenuBarIconState {
    case idle

    fileprivate var glyph: String {
        switch self {
        case .idle:
            "⟩˄⟨"
        }
    }

    fileprivate var accessibilityDescription: String {
        switch self {
        case .idle:
            "UpTil is idle"
        }
    }
}

enum MenuBarIconRenderer {
    private static let frameSize = NSSize(width: 20, height: 20)
    private static let angleFontSize: CGFloat = 18
    private static let arrowFontSize: CGFloat = 14
    private static let idleImage = makeImage(for: .idle)

    static func image(for _: MenuBarIconState) -> NSImage {
        idleImage
    }

    private static func makeImage(for state: MenuBarIconState) -> NSImage {
        let glyph = NSMutableAttributedString(
            string: state.glyph,
            attributes: [
                .font: NSFont.systemFont(ofSize: angleFontSize, weight: .regular),
                .foregroundColor: NSColor.black,
                .kern: -0.75,
            ]
        )
        glyph.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: arrowFontSize, weight: .light),
            range: NSRange(location: 1, length: 1)
        )
        glyph.addAttribute(
            .baselineOffset,
            value: 1.0,
            range: NSRange(location: 1, length: 1)
        )
        let glyphSize = glyph.size()
        let drawingPoint = NSPoint(
            x: (frameSize.width - glyphSize.width) / 2,
            y: (frameSize.height - glyphSize.height) / 2
        )

        let image = NSImage(size: frameSize)
        image.lockFocus()
        glyph.draw(at: drawingPoint)
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }
}

struct MenuBarLabel: View {
    @Bindable var controller: SessionController

    var body: some View {
        switch controller.session {
        case .idle:
            Image(nsImage: MenuBarIconRenderer.image(for: .idle))
                .accessibilityLabel("UpTil idle")
        case .indefinite:
            Image(nsImage: MenuBarActiveLabelRenderer.image(for: .indefinite))
                .accessibilityLabel("UpTil is active indefinitely")
        case let .timed(deadline):
            MenuBarCountdownView(deadline: deadline)
        }
    }
}
