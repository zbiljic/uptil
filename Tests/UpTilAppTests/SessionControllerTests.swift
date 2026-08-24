import Foundation
import Testing
@testable import UpTil
import UpTilCore

@MainActor
@Suite("Keep-awake session controller")
struct SessionControllerTests {
    private let startDate = Date(timeIntervalSinceReferenceDate: 1000)

    @Test("timed start from idle activates once and schedules its deadline")
    func timedStartActivatesAndSchedules() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 60))
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 0)
        #expect(fixture.controller.assertionIsActive)
        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(60)))
        #expect(fixture.scheduler.scheduledDeadlines == [startDate.addingTimeInterval(60)])
    }

    @Test("absolute start from idle activates once and schedules its exact deadline")
    func absoluteStartActivatesAndSchedules() {
        let fixture = makeController()
        let deadline = startDate.addingTimeInterval(90)

        #expect(fixture.controller.start(until: deadline))
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 0)
        #expect(fixture.controller.session == .timed(deadline: deadline))
        #expect(fixture.scheduler.scheduledDeadlines == [deadline])
    }

    @Test("absolute start replaces timed deadline without reactivation")
    func absoluteStartReplacesTimedDeadline() {
        let fixture = makeController()
        let replacement = startDate.addingTimeInterval(90)

        #expect(fixture.controller.start(for: 10))
        #expect(fixture.controller.start(until: replacement))

        #expect(fixture.service.activationCount == 1)
        #expect(fixture.controller.session == .timed(deadline: replacement))
        #expect(fixture.scheduler.scheduledDeadlines == [
            startDate.addingTimeInterval(10),
            replacement,
        ])
        #expect(fixture.scheduler.cancellationCount == 1)
    }

    @Test("absolute start replaces indefinite session without reactivation")
    func absoluteStartReplacesIndefiniteSession() {
        let fixture = makeController()
        let deadline = startDate.addingTimeInterval(90)

        fixture.controller.startIndefinitely()
        #expect(fixture.controller.start(until: deadline))

        #expect(fixture.service.activationCount == 1)
        #expect(fixture.controller.session == .timed(deadline: deadline))
        #expect(fixture.scheduler.scheduledDeadlines == [deadline])
    }

    @Test("invalid absolute starts do not mutate lifecycle state")
    func invalidAbsoluteStartDoesNothing() {
        let invalidDeadlines = [
            startDate,
            startDate.addingTimeInterval(-1),
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity),
        ]

        for deadline in invalidDeadlines {
            let fixture = makeController()
            fixture.controller.startIndefinitely()

            #expect(!fixture.controller.start(until: deadline))
            #expect(fixture.controller.session == .indefinite)
            #expect(fixture.service.activationCount == 1)
            #expect(fixture.service.deactivationCount == 0)
            #expect(fixture.scheduler.scheduledDeadlines.isEmpty)
            #expect(fixture.scheduler.cancellationCount == 0)
        }
    }

    @Test("indefinite start activates once and schedules nothing")
    func indefiniteStartActivatesWithoutScheduling() {
        let fixture = makeController()

        fixture.controller.startIndefinitely()

        #expect(fixture.service.activationCount == 1)
        #expect(fixture.controller.session == .indefinite)
        #expect(fixture.scheduler.scheduledDeadlines.isEmpty)
    }

    @Test("starting again while active replaces state without a second activation")
    func activeStartReplacesStateWithoutReactivation() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        #expect(fixture.controller.start(for: 20))

        #expect(fixture.service.activationCount == 1)
        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(20)))
        #expect(fixture.scheduler.scheduledDeadlines.count == 2)
        #expect(fixture.scheduler.cancellationCount == 1)
    }

    @Test("extensions reschedule without reactivating")
    func extensionsRescheduleWithoutReactivation() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        #expect(fixture.controller.extend(by: 5))
        #expect(fixture.controller.extend(by: 10))

        #expect(fixture.service.activationCount == 1)
        #expect(fixture.scheduler.scheduledDeadlines == [
            startDate.addingTimeInterval(10),
            startDate.addingTimeInterval(15),
            startDate.addingTimeInterval(25),
        ])
        #expect(fixture.scheduler.cancellationCount == 2)
    }

    @Test("extension from idle or indefinite changes nothing")
    func unavailableExtensionsDoNothing() {
        let fixture = makeController()

        #expect(!fixture.controller.extend(by: 10))
        fixture.controller.startIndefinitely()
        #expect(!fixture.controller.extend(by: 10))

        #expect(fixture.controller.session == .indefinite)
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.scheduler.scheduledDeadlines.isEmpty)
    }

    @Test("shortenings reschedule without changing keep-awake activation")
    func shorteningsRescheduleWithoutLifecycleChanges() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 120))
        #expect(fixture.controller.shorten(by: 30))
        #expect(fixture.controller.shorten(by: 15))

        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(75)))
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 0)
        #expect(fixture.scheduler.scheduledDeadlines == [
            startDate.addingTimeInterval(120),
            startDate.addingTimeInterval(90),
            startDate.addingTimeInterval(75),
        ])
        #expect(fixture.scheduler.cancellationCount == 2)
    }

    @Test("equal and oversized shortenings leave scheduling unchanged")
    func unavailableTimedShorteningsDoNothing() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 60))
        #expect(!fixture.controller.shorten(by: 60))
        #expect(!fixture.controller.shorten(by: 61))

        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(60)))
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 0)
        #expect(fixture.scheduler.scheduledDeadlines == [startDate.addingTimeInterval(60)])
        #expect(fixture.scheduler.cancellationCount == 0)
    }

    @Test("shortening from idle or indefinite changes nothing")
    func unavailableSessionShorteningsDoNothing() {
        let fixture = makeController()

        #expect(!fixture.controller.shorten(by: 10))
        fixture.controller.startIndefinitely()
        #expect(!fixture.controller.shorten(by: 10))

        #expect(fixture.controller.session == .indefinite)
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 0)
        #expect(fixture.scheduler.scheduledDeadlines.isEmpty)
        #expect(fixture.scheduler.cancellationCount == 0)
    }

    @Test("shortening validates against the time at interaction")
    func shorteningUsesCurrentClockValue() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 60))
        fixture.clock.currentDate = startDate.addingTimeInterval(29)
        #expect(fixture.controller.shorten(by: 30))
        fixture.clock.currentDate = startDate.addingTimeInterval(30)
        #expect(!fixture.controller.shorten(by: 1))

        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(30)))
        #expect(fixture.scheduler.scheduledDeadlines == [
            startDate.addingTimeInterval(60),
            startDate.addingTimeInterval(30),
        ])
        #expect(fixture.scheduler.cancellationCount == 1)
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 0)
    }

    @Test("an exact deadline callback stops and deactivates once")
    func exactDeadlineExpiresSession() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        fixture.clock.currentDate = startDate.addingTimeInterval(10)
        fixture.scheduler.fireScheduled(at: 0)

        #expect(fixture.controller.session == .idle)
        #expect(fixture.service.deactivationCount == 1)
        #expect(fixture.scheduler.cancellationCount == 1)
    }

    @Test("an overdue callback stops and deactivates once")
    func overdueDeadlineExpiresSession() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        fixture.clock.currentDate = startDate.addingTimeInterval(11)
        fixture.scheduler.fireScheduled(at: 0)

        #expect(fixture.controller.session == .idle)
        #expect(fixture.service.deactivationCount == 1)
    }

    @Test("an early stale callback reschedules and stays active")
    func earlyCallbackReschedulesCurrentDeadline() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        fixture.clock.currentDate = startDate.addingTimeInterval(2)
        fixture.scheduler.fireScheduled(at: 0)

        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(10)))
        #expect(fixture.service.isActive)
        #expect(fixture.service.deactivationCount == 0)
        #expect(fixture.scheduler.scheduledDeadlines == [
            startDate.addingTimeInterval(10),
            startDate.addingTimeInterval(10),
        ])
        #expect(fixture.scheduler.cancellationCount == 1)
    }

    @Test("explicit stop cancels expiry and deactivates once")
    func stopCancelsAndDeactivates() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        fixture.controller.stop()

        #expect(fixture.controller.session == .idle)
        #expect(fixture.scheduler.cancellationCount == 1)
        #expect(fixture.service.deactivationCount == 1)
    }

    @Test("repeated stop and shutdown remain idempotent")
    func repeatedStopAndShutdownAreIdempotent() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        fixture.controller.stop()
        fixture.controller.stop()
        fixture.controller.shutdown()

        #expect(fixture.service.deactivationCount == 1)
        #expect(fixture.scheduler.cancellationCount == 1)
    }

    @Test("starting after stop begins a new activation cycle")
    func startAfterStopReactivates() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        fixture.controller.stop()
        #expect(fixture.controller.start(for: 10))

        #expect(fixture.service.activationCount == 2)
        #expect(fixture.service.deactivationCount == 1)
        #expect(fixture.scheduler.scheduledDeadlines.count == 2)
    }

    @Test("invalid durations do not activate or schedule")
    func invalidDurationDoesNothing() {
        let fixture = makeController()

        #expect(!fixture.controller.start(for: 0))
        #expect(!fixture.controller.start(for: -1))
        #expect(!fixture.controller.start(for: .infinity))

        #expect(fixture.controller.session == .idle)
        #expect(fixture.service.activationCount == 0)
        #expect(fixture.scheduler.scheduledDeadlines.isEmpty)
    }

    @Test("switching timed to indefinite cancels expiry without releasing")
    func timedToIndefiniteKeepsAssertion() {
        let fixture = makeController()

        #expect(fixture.controller.start(for: 10))
        fixture.controller.startIndefinitely()

        #expect(fixture.controller.session == .indefinite)
        #expect(fixture.scheduler.cancellationCount == 1)
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 0)
    }

    @Test("switching indefinite to timed keeps one assertion and schedules expiry")
    func indefiniteToTimedKeepsAssertion() {
        let fixture = makeController()

        fixture.controller.startIndefinitely()
        #expect(fixture.controller.start(for: 10))

        #expect(fixture.controller.session == .timed(deadline: startDate.addingTimeInterval(10)))
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 0)
        #expect(fixture.scheduler.scheduledDeadlines == [startDate.addingTimeInterval(10)])
    }

    private func makeController() -> SessionControllerFixture {
        SessionControllerFixture(startDate: startDate)
    }
}

@MainActor
private final class SessionControllerFixture {
    let controller: SessionController
    let service: FakeKeepAwakeService
    let scheduler: ManualExpiryScheduler
    let clock: TestClock

    init(startDate: Date) {
        let service = FakeKeepAwakeService()
        let scheduler = ManualExpiryScheduler()
        let clock = TestClock(startDate)

        self.service = service
        self.scheduler = scheduler
        self.clock = clock
        controller = SessionController(
            keepAwakeService: service,
            expiryScheduler: scheduler
        ) {
            clock.currentDate
        }
    }
}
