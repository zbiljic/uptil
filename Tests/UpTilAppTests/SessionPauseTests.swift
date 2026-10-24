import Foundation
import Testing
@testable import UpTil
import UpTilCore

@MainActor
@Suite("Pause and resume")
struct SessionPauseTests {
    private let startDate = Date(timeIntervalSinceReferenceDate: 1000)

    @Test("pause freezes the timer, releases both assertions, and cancels expiry")
    func pauseReleasesAssertions() {
        let fixture = makeController(keepsDisplayAwake: true)
        #expect(fixture.controller.start(for: 720))
        fixture.clock.currentDate = startDate.addingTimeInterval(20)

        #expect(fixture.controller.pause())

        #expect(fixture.controller.session == .paused(remaining: 700))
        #expect(!fixture.controller.assertionIsActive)
        #expect(!fixture.service.isDisplaySleepPreventionActive)
        #expect(fixture.service.deactivationCount == 1)
        #expect(fixture.service.displayDisableCount == 1)
        #expect(fixture.scheduler.cancellationCount == 1)
        #expect(fixture.controller.keepsDisplayAwake)
    }

    @Test("resume restores assertions with the current preference and schedules the moved deadline")
    func resumeRestoresAssertionsAndSchedules() {
        let fixture = makeController()
        #expect(fixture.controller.start(for: 720))
        fixture.clock.currentDate = startDate.addingTimeInterval(20)
        #expect(fixture.controller.pause())
        fixture.clock.currentDate = startDate.addingTimeInterval(3600)

        fixture.controller.setKeepsDisplayAwake(true)

        #expect(fixture.preference.writes == [true])
        #expect(!fixture.service.isActive)
        #expect(fixture.service.displayEnableCount == 0)

        #expect(fixture.controller.resume())

        let resumedDeadline = startDate.addingTimeInterval(3600 + 700)
        #expect(fixture.controller.session == .timed(deadline: resumedDeadline))
        #expect(fixture.service.activationCount == 2)
        #expect(fixture.service.isDisplaySleepPreventionActive)
        #expect(fixture.scheduler.scheduledDeadlines == [startDate.addingTimeInterval(720), resumedDeadline])
    }

    @Test("a paused Until session ignores stale callbacks and clock changes, then expires at its moved deadline")
    func resumedUntilSessionExpiresAtMovedDeadline() {
        let fixture = makeController()
        let deadline = startDate.addingTimeInterval(90)
        #expect(fixture.controller.start(until: deadline))
        fixture.clock.currentDate = startDate.addingTimeInterval(30)
        #expect(fixture.controller.pause())

        for date in [startDate.addingTimeInterval(600), startDate.addingTimeInterval(-600)] {
            fixture.clock.currentDate = date
            fixture.scheduler.fireScheduled(at: 0)
            fixture.controller.reconcileClockChange()
            #expect(fixture.controller.session == .paused(remaining: 60))
        }
        #expect(fixture.scheduler.scheduledDeadlines == [deadline])
        #expect(!fixture.service.isActive)

        fixture.clock.currentDate = startDate.addingTimeInterval(600)
        #expect(fixture.controller.resume())
        let resumedDeadline = startDate.addingTimeInterval(660)
        fixture.scheduler.fireScheduled(at: 0)
        #expect(fixture.controller.session == .timed(deadline: resumedDeadline))

        fixture.clock.currentDate = resumedDeadline
        fixture.scheduler.fireScheduled(at: fixture.scheduler.scheduledDeadlines.count - 1)
        #expect(fixture.controller.session == .idle)
        #expect(!fixture.service.isActive)
        #expect(fixture.service.deactivationCount == 2)
    }

    @Test("pausing a timer that already ended makes it idle instead")
    func pauseAfterExpiryBecomesIdle() {
        let fixture = makeController(keepsDisplayAwake: true)
        #expect(fixture.controller.start(for: 60))
        fixture.clock.currentDate = startDate.addingTimeInterval(60)

        #expect(!fixture.controller.pause())

        #expect(fixture.controller.session == .idle)
        #expect(!fixture.service.isActive)
        #expect(!fixture.service.isDisplaySleepPreventionActive)
        #expect(fixture.service.deactivationCount == 1)
    }

    @Test("pause and resume outside their states have no side effects")
    func unavailableActionsDoNothing() {
        let fixture = makeController()
        #expect(!fixture.controller.pause())
        #expect(!fixture.controller.resume())
        fixture.controller.startIndefinitely()
        #expect(!fixture.controller.pause())
        #expect(!fixture.controller.resume())
        #expect(fixture.controller.session == .indefinite)

        #expect(fixture.controller.start(for: 60))
        #expect(!fixture.controller.resume())
        #expect(fixture.controller.pause())
        #expect(!fixture.controller.pause())

        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 1)
        #expect(fixture.scheduler.scheduledDeadlines == [startDate.addingTimeInterval(60)])
        #expect(fixture.controller.resume())
        #expect(!fixture.controller.resume())
        #expect(fixture.service.activationCount == 2)
    }

    @Test("rejected actions keep a paused session, starts replace it, and Stop or Quit discard it")
    func pausedSessionReplacementAndDiscard() {
        let fixture = makeController()
        #expect(fixture.controller.start(for: 60))
        #expect(fixture.controller.pause())
        #expect(!fixture.controller.start(for: 0))
        #expect(!fixture.controller.extend(by: 60))
        #expect(!fixture.controller.shorten(by: 10))
        #expect(fixture.controller.session == .paused(remaining: 60))
        #expect(fixture.service.activationCount == 1)

        #expect(fixture.controller.start(for: 30))
        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(30)))
        #expect(fixture.service.activationCount == 2)

        #expect(fixture.controller.pause())
        fixture.controller.stop()
        #expect(fixture.controller.session == .idle)
        #expect(!fixture.controller.resume())

        #expect(fixture.controller.start(for: 60))
        #expect(fixture.controller.pause())
        fixture.controller.shutdown()
        #expect(fixture.controller.session == .idle)
        #expect(!fixture.service.isActive)
    }

    private func makeController(keepsDisplayAwake: Bool = false) -> SessionControllerFixture {
        SessionControllerFixture(startDate: startDate, keepsDisplayAwake: keepsDisplayAwake)
    }
}

extension SessionPauseTests {
    @Test("paused presentation offers Resume and Stop and disables the duration rows")
    func pausedPresentation() {
        let session = KeepAwakeSession.paused(remaining: 720)
        let presentation = SessionPresentationState(session: session)

        #expect(presentation == .paused)
        #expect(presentation.quickDurationActions == [.extend, .shorten])
        for action in presentation.quickDurationActions {
            for choice in presentation.quickDurationChoices {
                #expect(!action.isEnabled(for: choice, session: session, at: startDate))
            }
        }
        #expect(presentation.canStop)
        #expect(!presentation.canStartUntil)
        #expect(SessionPauseAction(state: .paused) == .resume)
        #expect(SessionPauseAction(state: .timed) == .pause)
        #expect(SessionPauseAction(state: .idle) == nil)
        #expect(SessionPauseAction(state: .indefinite) == nil)
        #expect(presentation.stopAccessibilityLabel == "Stop the paused session and discard its remaining time")
        #expect(SessionPresentationState.timed.stopAccessibilityLabel == "Stop the active session")
    }

    @Test("pause controls explain sleep and route through the controller")
    func pauseActionRouting() {
        #expect(SessionPauseAction.pause.title == "Pause")
        #expect(SessionPauseAction.resume.title == "Resume")
        #expect(SessionPauseAction.pause.accessibilityLabel == "Pause the session")
        #expect(SessionPauseAction.pause.accessibilityHint == "Lets the Mac sleep and keeps the remaining time")
        #expect(SessionPauseAction.resume.accessibilityLabel == "Resume the session")
        #expect(SessionPauseAction.resume.accessibilityHint == "Keeps the Mac awake again for the remaining time")

        let fixture = makeController()
        #expect(fixture.controller.start(for: 60))
        #expect(SessionPauseAction.pause.perform(controller: fixture.controller))
        #expect(fixture.controller.session == .paused(remaining: 60))
        #expect(SessionPauseAction.resume.perform(controller: fixture.controller))
        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(60)))
    }

    @Test("paused text shows no end time and stays accessible")
    func pausedText() {
        let english = Locale(identifier: "en_US")
        #expect(PausedSessionPresentation.caption == "Paused — Mac may sleep")
        #expect(PausedSessionPresentation.accessibilityLabel(remaining: 720, locale: english) ==
            "Paused with 12 minutes remaining. The Mac may sleep.")
        #expect(DisplayAwakeTogglePresentation.pausedDescription == "Applies when the session resumes")
    }

    @Test("the paused menu bar label is a static template image")
    func pausedMenuBarLabel() {
        let paused = MenuBarActiveLabelContent.paused(MenuBarCountdownFormatting.durationString(remaining: 720))

        #expect(paused.display == "⟩Ⅱ 12m⟨")
        #expect(paused.accessibilityLabel == "UpTil paused, 12m remaining. The Mac may sleep.")
        let image = MenuBarActiveLabelRenderer.image(for: paused)
        #expect(image.isTemplate)
        #expect(image.size.height == 20)
        #expect(image.size.width > MenuBarActiveLabelRenderer.image(for: .countdown("12m")).size.width)
    }
}
