import AppKit
import SwiftUI
import Testing
@testable import UpTil

@MainActor
@Suite("Popover layout", .serialized)
struct PopoverLayoutTests {
    @Test("native popover geometry stays fixed through session and display changes", arguments: ["en_US", "en_GB"])
    func geometryStaysFixed(locale: String) async throws {
        let controller = SessionController(
            keepAwakeService: FakeKeepAwakeService(),
            displaySleepPreference: FakeDisplaySleepPreference(),
            expiryScheduler: ManualExpiryScheduler()
        )
        let host = NSHostingView(rootView: SessionPopover(controller: controller)
            .environment(\.locale, Locale(identifier: locale))
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        var sizes: [NSSize] = []
        for state in ["idle", "timed", "extended", "display", "under-minute", "tick", "indefinite", "stopped"] {
            switch state {
            case "timed": controller.start(for: 15 * 60)
            case "extended": controller.extend(by: 75 * 60)
            case "display": controller.setKeepsDisplayAwake(true)
            case "under-minute": controller.start(for: 45)
            case "tick": try await Task.sleep(for: .milliseconds(1200))
            case "indefinite": controller.startIndefinitely()
            case "stopped": controller.stop()
            default: break
            }
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            host.setFrameSize(size)
            window.setContentSize(size)
            host.layoutSubtreeIfNeeded()
            try await render(host, name: "\(locale)-\(state)")
            sizes.append(host.fittingSize)
        }
        let baselineSize = try #require(sizes.first)
        #expect(baselineSize.width == 300)
        #expect(sizes.allSatisfy { $0 == baselineSize })
    }

    private func render(_ host: NSView, name: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UpTilPopoverRefinementReview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let details = "size=\(host.fittingSize)"
        try details.write(to: directory.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            host.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(30))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(appearance.rawValue).png"))
        }
    }
}
