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

    @Test("active menu bar labels use paired angles and a template image")
    func activeMenuBarLabelsUsePairedAnglesAndTemplateImage() {
        #expect(MenuBarActiveLabelContent.countdown("42m").display == "⟩42m⟨")
        #expect(MenuBarActiveLabelContent.indefinite.display == "⟩∞⟨")

        let indefinite = MenuBarActiveLabelRenderer.image(for: .indefinite)

        #expect(indefinite.size.width > 0)
        #expect(indefinite.size.height == 20)
        #expect(indefinite.isTemplate)
    }

    @Test("idle presentation exposes four fixed quick starts")
    func idlePresentationUsesFixedQuickChoices() {
        let presentation = SessionPresentationState(session: .idle)

        #expect(presentation.quickDurationAction == .start)
        #expect(presentation.quickDurationChoices == QuickDurationChoice.allCases)
        #expect(presentation.quickDurationChoices.map(\.duration) == [900, 1800, 3600, 7200])
        #expect(presentation.canStartUntil)
        #expect(!presentation.canStop)
    }

    @Test("timed presentation reuses quick choice identity and order")
    func timedPresentationUsesStableQuickChoices() {
        let idle = SessionPresentationState(session: .idle)
        let timed = SessionPresentationState(session: .timed(deadline: Date()))

        #expect(timed.quickDurationAction == .extend)
        #expect(timed.quickDurationChoices.map(\.id) == idle.quickDurationChoices.map(\.id))
        #expect(timed.quickDurationChoices.map(\.duration) == idle.quickDurationChoices.map(\.duration))
        #expect(timed.canStop)
    }

    @Test("quick durations do not expose a five minute choice")
    func quickDurationsExcludeFiveMinutes() {
        let idle = SessionPresentationState(session: .idle)
        let timed = SessionPresentationState(session: .timed(deadline: Date()))

        #expect(!idle.quickDurationChoices.map(\.duration).contains(300))
        #expect(!timed.quickDurationChoices.map(\.duration).contains(300))
    }

    @Test("indefinite presentation has no duration actions")
    func indefinitePresentationHidesQuickDurations() {
        let presentation = SessionPresentationState(session: .indefinite)

        #expect(presentation.quickDurationAction == nil)
        #expect(presentation.quickDurationChoices.isEmpty)
        #expect(!presentation.canStartUntil)
        #expect(presentation.canStop)
    }

    @Test("quick duration titles reflect the current action")
    func quickDurationTitlesReflectAction() {
        let choices = QuickDurationChoice.allCases

        #expect(choices.map { QuickDurationAction.start.title(for: $0) } == ["15m", "30m", "1h", "2h"])
        #expect(choices.map { QuickDurationAction.extend.title(for: $0) } == ["+15m", "+30m", "+1h", "+2h"])
    }

    @Test("quick duration accessibility labels describe full actions")
    func quickDurationAccessibilityLabelsDescribeActions() {
        let choices = QuickDurationChoice.allCases

        #expect(choices.map { QuickDurationAction.start.accessibilityLabel(for: $0) } == [
            "Start a 15 minute session",
            "Start a 30 minute session",
            "Start a 1 hour session",
            "Start a 2 hour session",
        ])
        #expect(choices.map { QuickDurationAction.extend.accessibilityLabel(for: $0) } == [
            "Extend the session by 15 minutes",
            "Extend the session by 30 minutes",
            "Extend the session by 1 hour",
            "Extend the session by 2 hours",
        ])
    }

    @Test("Until remains available only while idle")
    func untilAvailabilityRemainsIdleOnly() {
        #expect(SessionPresentationState(session: .idle).canStartUntil)
        #expect(!SessionPresentationState(session: .timed(deadline: Date())).canStartUntil)
        #expect(!SessionPresentationState(session: .indefinite).canStartUntil)
    }

    @Test("repeated quick action routing extends the stored deadline")
    func repeatedQuickActionRoutingIsAdditive() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let service = FakeKeepAwakeService()
        let scheduler = ManualExpiryScheduler()
        let controller = SessionController(
            keepAwakeService: service,
            expiryScheduler: scheduler
        ) { now }
        let choice = QuickDurationChoice.fifteenMinutes

        #expect(QuickDurationAction.start.perform(choice: choice, controller: controller))
        for _ in 0 ..< 3 {
            #expect(QuickDurationAction.extend.perform(choice: choice, controller: controller))
        }

        let expectedDeadline = now.addingTimeInterval(3600)
        #expect(controller.session == .timed(deadline: expectedDeadline))
        #expect(service.activationCount == 1)
        #expect(scheduler.scheduledDeadlines.count == 4)
        #expect(scheduler.scheduledDeadlines.last == expectedDeadline)
        #expect(scheduler.cancellationCount == 3)
        #expect(service.deactivationCount == 0)
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
