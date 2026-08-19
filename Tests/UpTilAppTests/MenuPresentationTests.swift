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
        #expect(presentation.canStartUntil)
        #expect(presentation.extensionChoices.isEmpty)
    }

    @Test("timed presentation exposes additive extension choices")
    func timedPresentationUsesFixedExtensionChoices() {
        let presentation = SessionPresentationState(session: .timed(deadline: Date()))

        #expect(presentation.startChoices.isEmpty)
        #expect(!presentation.canStartUntil)
        #expect(presentation.extensionChoices == SessionExtensionChoice.allCases)
        #expect(presentation.extensionChoices.map(\.duration) == [300, 900, 1800, 3600])
    }

    @Test("indefinite presentation has no extension actions")
    func indefinitePresentationHidesExtensions() {
        let presentation = SessionPresentationState(session: .indefinite)

        #expect(presentation.startChoices.isEmpty)
        #expect(!presentation.canStartUntil)
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

    @Test("until preview distinguishes today and tomorrow")
    func untilPreviewDistinguishesDay() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19,
            hour: 10
        )))
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19,
            hour: 18,
            minute: 30
        )))
        let tomorrow = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 20,
            hour: 8,
            minute: 15
        )))

        #expect(UntilDeadlineFormatting.string(
            for: today,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_GB"),
            timeZone: timeZone
        ) == "Today, 18:30")
        #expect(UntilDeadlineFormatting.string(
            for: tomorrow,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_GB"),
            timeZone: timeZone
        ) == "Tomorrow, 08:15")
    }

    @Test("until preview follows a twelve-hour locale")
    func untilPreviewUsesInjectedLocale() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19,
            hour: 10
        )))
        let deadline = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19,
            hour: 18,
            minute: 30
        )))
        let preview = UntilDeadlineFormatting.string(
            for: deadline,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone
        )

        #expect(preview.hasPrefix("Today, "))
        #expect(preview.contains("6:30"))
        #expect(preview.contains("PM"))
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
