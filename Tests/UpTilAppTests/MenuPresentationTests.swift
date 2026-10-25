import AppKit
import Foundation
import Testing
@testable import UpTil
import UpTilCore

@MainActor
@Suite("Menu presentation")
struct MenuPresentationTests {
    @Test("display-awake toggle presentation remains stable")
    func displayAwakeTogglePresentationIsStable() {
        #expect(DisplayAwakeTogglePresentation.label == "Keep display awake")
        #expect(DisplayAwakeTogglePresentation.systemImage == "display")
        #expect(DisplayAwakeTogglePresentation.description == "During sessions only")
    }

    @Test("display-awake toggle routes through the controller")
    func displayAwakeToggleRoutesThroughController() {
        let service = FakeKeepAwakeService()
        let preference = FakeDisplaySleepPreference()
        let controller = SessionController(
            keepAwakeService: service,
            displaySleepPreference: preference
        )

        DisplayAwakeTogglePresentation.perform(isEnabled: true, controller: controller)

        #expect(controller.keepsDisplayAwake)
        #expect(preference.writes == [true])
        #expect(!service.isActive)
        #expect(!service.isDisplaySleepPreventionActive)
    }

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

        #expect(presentation.quickDurationActions == [.start, .shorten])
        #expect(presentation.quickDurationChoices == QuickDurationChoice.allCases)
        #expect(presentation.quickDurationChoices.map(\.duration) == [900, 1800, 3600, 7200])
        #expect(presentation.canStartUntil)
        #expect(!presentation.canStop)
    }

    @Test("timed presentation reuses quick choice identity and order")
    func timedPresentationUsesStableQuickChoices() {
        let idle = SessionPresentationState(session: .idle)
        let timed = SessionPresentationState(session: .timed(deadline: Date()))

        #expect(timed.quickDurationActions == [.extend, .shorten])
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

    @Test("indefinite presentation lets quick additions set an end")
    func indefinitePresentationKeepsQuickDurations() {
        let presentation = SessionPresentationState(session: .indefinite)

        #expect(presentation.quickDurationActions == [.limit, .shorten])
        #expect(presentation.quickDurationChoices == QuickDurationChoice.allCases)
        for choice in presentation.quickDurationChoices {
            #expect(QuickDurationAction.limit.isEnabled(for: choice, session: .indefinite, at: Date()))
            #expect(!QuickDurationAction.shorten.isEnabled(for: choice, session: .indefinite, at: Date()))
        }
        #expect(!presentation.canStartUntil)
        #expect(presentation.canStop)
    }

    @Test("quick duration titles reflect the current action")
    func quickDurationTitlesReflectAction() {
        let choices = QuickDurationChoice.allCases

        #expect(choices.map(\.title) == ["15m", "30m", "1h", "2h"])
        #expect(QuickDurationAction.start.sign == "+")
        #expect(QuickDurationAction.extend.sign == "+")
        #expect(QuickDurationAction.limit.sign == "+")
        #expect(QuickDurationAction.shorten.sign == "−")
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
        #expect(choices.map { QuickDurationAction.limit.accessibilityLabel(for: $0) } == [
            "End the session in 15 minutes",
            "End the session in 30 minutes",
            "End the session in 1 hour",
            "End the session in 2 hours",
        ])
        #expect(choices.map { QuickDurationAction.shorten.accessibilityLabel(for: $0) } == [
            "Shorten the session by 15 minutes",
            "Shorten the session by 30 minutes",
            "Shorten the session by 1 hour",
            "Shorten the session by 2 hours",
        ])
    }

    @Test("quick duration enabled state enforces strict shortening boundaries")
    func quickDurationEnabledStateUsesDomainBoundary() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let choice = QuickDurationChoice.fifteenMinutes
        let above = KeepAwakeSession.timed(deadline: now.addingTimeInterval(choice.duration + 0.001))
        let equal = KeepAwakeSession.timed(deadline: now.addingTimeInterval(choice.duration))
        let below = KeepAwakeSession.timed(deadline: now.addingTimeInterval(choice.duration - 0.001))

        #expect(QuickDurationAction.start.isEnabled(for: choice, session: .idle, at: now))
        #expect(!QuickDurationAction.start.isEnabled(for: choice, session: above, at: now))
        #expect(!QuickDurationAction.start.isEnabled(for: choice, session: .indefinite, at: now))
        #expect(!QuickDurationAction.extend.isEnabled(for: choice, session: .idle, at: now))
        #expect(!QuickDurationAction.extend.isEnabled(for: choice, session: .indefinite, at: now))
        #expect(QuickDurationAction.extend.isEnabled(for: choice, session: above, at: now))
        #expect(QuickDurationAction.limit.isEnabled(for: choice, session: .indefinite, at: now))
        #expect(!QuickDurationAction.limit.isEnabled(for: choice, session: .idle, at: now))
        #expect(!QuickDurationAction.limit.isEnabled(for: choice, session: above, at: now))
        #expect(QuickDurationAction.shorten.isEnabled(for: choice, session: above, at: now))
        #expect(!QuickDurationAction.shorten.isEnabled(for: choice, session: equal, at: now))
        #expect(!QuickDurationAction.shorten.isEnabled(for: choice, session: below, at: now))
        #expect(!QuickDurationAction.shorten.isEnabled(for: choice, session: .idle, at: now))
        #expect(!QuickDurationAction.shorten.isEnabled(for: choice, session: .indefinite, at: now))
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

    @Test("quick shorten action routes through controller and replaces schedule")
    func quickShortenActionRoutesThroughController() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let service = FakeKeepAwakeService()
        let scheduler = ManualExpiryScheduler()
        let controller = SessionController(
            keepAwakeService: service,
            expiryScheduler: scheduler
        ) { now }

        #expect(controller.start(for: 3600))
        #expect(QuickDurationAction.shorten.perform(
            choice: .fifteenMinutes,
            controller: controller
        ))

        let expectedDeadline = now.addingTimeInterval(2700)
        #expect(controller.session == .timed(deadline: expectedDeadline))
        #expect(service.activationCount == 1)
        #expect(service.deactivationCount == 0)
        #expect(scheduler.scheduledDeadlines == [
            now.addingTimeInterval(3600),
            expectedDeadline,
        ])
        #expect(scheduler.cancellationCount == 1)
    }

    @Test("end time formatting is deterministic for an injected locale and time zone")
    func endTimeFormattingUsesInjectedEnvironment() {
        let timeZone = TimeZone(secondsFromGMT: 0) ?? .autoupdatingCurrent

        #expect(
            EndTimeFormatting.string(
                for: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 0),
                locale: Locale(identifier: "en_GB"),
                timeZone: timeZone
            ) == "today at 00:00"
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
        ) == "Ends today at 18:30 · 8h 30m")
        #expect(UntilDeadlineFormatting.string(
            for: tomorrow,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_GB"),
            timeZone: timeZone
        ) == "Ends tomorrow at 08:15 · 22h 15m")
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

        #expect(preview.hasPrefix("Ends today at "))
        #expect(preview.contains("6:30"))
        #expect(preview.contains("PM"))
    }
}

extension MenuPresentationTests {
    @Test("Until action submits the displayed absolute deadline")
    func untilActionSubmitsDisplayedDeadline() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let beforeNoon = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19,
            hour: 11,
            minute: 59,
            second: 59
        )))
        let afterNoon = beforeNoon.addingTimeInterval(2)
        let selection = try #require(calendar.date(from: DateComponents(hour: 12)))
        let displayedDeadline = try #require(WallClockDeadline.nextOccurrence(
            of: selection,
            after: beforeNoon,
            calendar: calendar
        ))
        let fixture = SessionControllerFixture(startDate: beforeNoon, keepsDisplayAwake: false)
        let control = IdleStartControls(controller: fixture.controller)

        let todayPreview = UntilDeadlineFormatting.string(
            for: displayedDeadline,
            now: beforeNoon,
            calendar: calendar,
            locale: Locale(identifier: "en_GB"),
            timeZone: timeZone
        )
        #expect(todayPreview.hasPrefix("Ends today at "))

        fixture.clock.currentDate = afterNoon
        #expect(!control.startUntil(displayedDeadline))
        #expect(fixture.controller.session == .idle)
        #expect(fixture.service.activationCount == 0)
        #expect(fixture.scheduler.scheduledDeadlines.isEmpty)

        let refreshedDeadline = try #require(WallClockDeadline.nextOccurrence(
            of: selection,
            after: afterNoon,
            calendar: calendar
        ))
        let tomorrowPreview = UntilDeadlineFormatting.string(
            for: refreshedDeadline,
            now: afterNoon,
            calendar: calendar,
            locale: Locale(identifier: "en_GB"),
            timeZone: timeZone
        )
        #expect(tomorrowPreview.hasPrefix("Ends tomorrow at "))
        #expect(control.startUntil(refreshedDeadline))
        #expect(fixture.controller.session == .timed(deadline: refreshedDeadline))
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.scheduler.scheduledDeadlines == [refreshedDeadline])

        let freshFixture = SessionControllerFixture(startDate: beforeNoon, keepsDisplayAwake: false)
        let freshControl = IdleStartControls(controller: freshFixture.controller)
        #expect(freshControl.startUntil(displayedDeadline))
        #expect(freshFixture.controller.session == .timed(deadline: displayedDeadline))
        #expect(freshFixture.scheduler.scheduledDeadlines == [displayedDeadline])

        let equalFixture = SessionControllerFixture(startDate: displayedDeadline, keepsDisplayAwake: false)
        #expect(!IdleStartControls(controller: equalFixture.controller).startUntil(displayedDeadline))
        #expect(equalFixture.controller.session == .idle)
        #expect(equalFixture.service.activationCount == 0)
        #expect(equalFixture.scheduler.scheduledDeadlines.isEmpty)
    }

    @Test("a quick addition turns an indefinite session into a timed one")
    func quickLimitConvertsIndefiniteSession() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let service = FakeKeepAwakeService()
        let scheduler = ManualExpiryScheduler()
        let controller = SessionController(
            keepAwakeService: service,
            expiryScheduler: scheduler
        ) { now }
        controller.startIndefinitely()
        #expect(QuickDurationAction.limit.perform(choice: .oneHour, controller: controller))
        #expect(controller.session == .timed(deadline: now.addingTimeInterval(3600)))
        #expect(SessionPresentationState(session: controller.session).quickDurationActions == [.extend, .shorten])
        #expect(QuickDurationAction.extend.perform(choice: .fifteenMinutes, controller: controller))
        #expect(controller.session == .timed(deadline: now.addingTimeInterval(4500)))
        #expect(service.activationCount == 1)
        #expect(service.deactivationCount == 0)
        #expect(scheduler.scheduledDeadlines == [now.addingTimeInterval(3600), now.addingTimeInterval(4500)])
    }

    @Test("quit shuts down before invoking termination")
    func quitActionCleansUpBeforeTermination() {
        let service = FakeKeepAwakeService()
        let scheduler = ManualExpiryScheduler()
        let preference = FakeDisplaySleepPreference(isEnabled: true)
        let controller = SessionController(
            keepAwakeService: service,
            displaySleepPreference: preference,
            expiryScheduler: scheduler
        )
        #expect(controller.start(for: 60))
        #expect(service.isDisplaySleepPreventionActive)

        var servicesWereStopped = false
        AppQuitAction.perform(controller: controller) {
            servicesWereStopped = !service.isActive && !service.isDisplaySleepPreventionActive
        }

        #expect(servicesWereStopped)
        #expect(service.deactivationCount == 1)
        #expect(service.displayDisableCount == 1)
        #expect(controller.session == .idle)
        #expect(controller.keepsDisplayAwake)
    }
}

extension MenuPresentationTests {
    @Test("menu bar images stay compact and fit their content")
    func menuBarWidthFitsContent() {
        let idle = MenuBarIconRenderer.image(for: .idle)
        #expect(idle.size == NSSize(width: 20, height: 20))
        let short = MenuBarActiveLabelRenderer.image(for: .countdown("1m"))
        let longer = MenuBarActiveLabelRenderer.image(for: .countdown("1h30m"))
        #expect(longer.size.width > short.size.width)
        for content in [
            MenuBarActiveLabelContent.indefinite,
            .countdown("1m"),
            .countdown("1h30m"),
            .countdown("999999999999999h"),
        ] {
            let image = MenuBarActiveLabelRenderer.image(for: content)
            #expect(image.size.width > 0)
            #expect(image.size.height == 20)
            #expect(image.isTemplate)
            #expect(image.accessibilityDescription == content.display)
        }
    }

    @Test("end date follows local midnight, tomorrow, and later years")
    func endDateIncludesLocalDay() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let west = try #require(TimeZone(secondsFromGMT: -8 * 3600))
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 0)
        let nextDay = now.addingTimeInterval(24 * 3600)
        let english = Locale(identifier: "en_GB")
        #expect(EndTimeFormatting.string(
            for: nextDay,
            now: now,
            calendar: calendar,
            locale: english,
            timeZone: utc
        ) == "tomorrow at 00:00")
        #expect(EndTimeFormatting.string(
            for: now,
            now: now.addingTimeInterval(-3600),
            calendar: calendar,
            locale: english,
            timeZone: utc
        ) == "tomorrow at 00:00")
        #expect(EndTimeFormatting.string(
            for: now,
            now: now.addingTimeInterval(-3600),
            calendar: calendar,
            locale: english,
            timeZone: west
        ) == "today at 16:00")
        let twelveHour = EndTimeFormatting.string(
            for: now,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: west
        )
        #expect(twelveHour.contains("4:00"))
        #expect(twelveHour.contains("PM"))
        let later = try #require(ISO8601DateFormatter().date(from: "2027-01-02T18:30:00Z"))
        #expect(EndTimeFormatting.string(
            for: later,
            now: now,
            calendar: calendar,
            locale: english,
            timeZone: utc
        ) == "02/01/2027, 18:30")
    }
}
