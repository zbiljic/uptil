import AppKit
import Foundation
import Testing
@testable import UpTil
import UpTilCore

@MainActor
@Suite("Menu presentation")
struct MenuPresentationTests {
    @Test("idle menu bar icon uses a fixed-size template frame")
    func idleMenuBarIconUsesFixedSizeTemplateFrame() {
        let idle = MenuBarIconRenderer.image(for: .idle)

        #expect(idle.size.width > 0)
        #expect(idle.size.height > 0)
        #expect(idle.isTemplate)
        #expect(idle.accessibilityDescription?.isEmpty == false)
    }

    @Test("idle presentation exposes the four fixed starts")
    func idlePresentationUsesFixedStartChoices() {
        let presentation = SessionPresentationState(session: .idle)

        #expect(presentation.startChoices == SessionStartChoice.allCases)
        #expect(presentation.startChoices.map(\.duration) == [900, 1800, 3600, 7200])
        #expect(presentation.extensionChoices.isEmpty)
    }

    @Test("timed presentation exposes additive extension choices")
    func timedPresentationUsesFixedExtensionChoices() {
        let presentation = SessionPresentationState(session: .timed(deadline: Date()))

        #expect(presentation.startChoices.isEmpty)
        #expect(presentation.extensionChoices == SessionExtensionChoice.allCases)
        #expect(presentation.extensionChoices.map(\.duration) == [300, 900, 1800, 3600])
    }

    @Test("indefinite presentation has no extension actions")
    func indefinitePresentationHidesExtensions() {
        let presentation = SessionPresentationState(session: .indefinite)

        #expect(presentation.startChoices.isEmpty)
        #expect(presentation.extensionChoices.isEmpty)
    }

    @Test("end time formatting is deterministic for an injected locale and time zone")
    func endTimeFormattingUsesInjectedEnvironment() {
        let timeZone = TimeZone(secondsFromGMT: 0) ?? .autoupdatingCurrent

        #expect(
            EndTimeFormatting.string(
                for: Date(timeIntervalSince1970: 0),
                locale: Locale(identifier: "en_GB"),
                timeZone: timeZone
            ) == "UpTil 00:00"
        )
    }

    @Test("quit shuts down before invoking termination")
    func quitActionCleansUpBeforeTermination() {
        let service = FakeKeepAwakeService()
        let scheduler = ManualExpiryScheduler()
        let controller = SessionController(
            keepAwakeService: service,
            expiryScheduler: scheduler
        )
        #expect(controller.start(for: 60))

        var serviceWasStopped = false
        AppQuitAction.perform(controller: controller) {
            serviceWasStopped = !service.isActive
        }

        #expect(serviceWasStopped)
        #expect(controller.session == .idle)
    }
}
