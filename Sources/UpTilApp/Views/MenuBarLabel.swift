import AppKit
import SwiftUI
import UpTilCore

enum MenuBarIconState {
    case idle
    case active

    init(session: KeepAwakeSession) {
        self = session.isActive ? .active : .idle
    }

    fileprivate var symbolName: String {
        switch self {
        case .idle:
            "timer"
        case .active:
            "timer.circle.fill"
        }
    }

    fileprivate var accessibilityDescription: String {
        switch self {
        case .idle:
            "UpTil is idle"
        case .active:
            "UpTil is keeping the Mac awake"
        }
    }
}

enum MenuBarIconRenderer {
    private static let frameSize = NSSize(width: 18, height: 18)
    private static let idleImage = makeImage(for: .idle)
    private static let activeImage = makeImage(for: .active)

    static func image(for state: MenuBarIconState) -> NSImage {
        switch state {
        case .idle:
            idleImage
        case .active:
            activeImage
        }
    }

    private static func makeImage(for state: MenuBarIconState) -> NSImage {
        guard
            let symbol = NSImage(
                systemSymbolName: state.symbolName,
                accessibilityDescription: state.accessibilityDescription
            )
        else {
            preconditionFailure("Missing required SF Symbol: \(state.symbolName)")
        }

        let configuredSymbol = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        ) ?? symbol
        let symbolSize = configuredSymbol.size
        let scale = min(frameSize.width / symbolSize.width, frameSize.height / symbolSize.height)
        let drawingSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        let drawingRect = NSRect(
            x: (frameSize.width - drawingSize.width) / 2,
            y: (frameSize.height - drawingSize.height) / 2,
            width: drawingSize.width,
            height: drawingSize.height
        )

        let image = NSImage(size: frameSize)
        image.lockFocus()
        configuredSymbol.draw(in: drawingRect)
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }
}

struct MenuBarLabel: View {
    @Bindable var controller: SessionController

    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(for: MenuBarIconState(session: controller.session)))
            .accessibilityLabel(controller.session.isActive ? "UpTil active" : "UpTil idle")
    }
}
