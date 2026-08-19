import Foundation
import Testing
@testable import UpTilCore

@Suite("KeepAwakeSession")
struct KeepAwakeSessionTests {
    private let now = Date(timeIntervalSince1970: 1000)

    @Test("starts idle with inactive queries")
    func defaultStateIsIdle() {
        let session = KeepAwakeSession.idle

        #expect(session.isActive == false)
        #expect(session.deadline == nil)
        #expect(session.remaining(at: now) == nil)
        #expect(session.isExpired(at: now) == false)
    }

    @Test("computes a timed deadline from the supplied time")
    func timedStartComputesDeadline() {
        var session = KeepAwakeSession.idle

        let started = session.start(for: 90, now: now)

        #expect(started)
        #expect(session == .timed(deadline: now.addingTimeInterval(90)))
    }

    @Test("starts an indefinite session")
    func indefiniteStart() {
        var session = KeepAwakeSession.idle

        session.startIndefinitely()

        #expect(session == .indefinite)
        #expect(session.isActive)
        #expect(session.deadline == nil)
        #expect(session.remaining(at: now) == nil)
    }

    @Test("replaces an active timed session using the supplied time")
    func timedStartReplacesActiveState() {
        var session = KeepAwakeSession.timed(deadline: now.addingTimeInterval(10))

        let started = session.start(for: 20, now: now.addingTimeInterval(100))

        #expect(started)
        #expect(session == .timed(deadline: now.addingTimeInterval(120)))
    }

    @Test("replaces an active indefinite session")
    func timedStartReplacesIndefiniteState() {
        var session = KeepAwakeSession.indefinite

        let started = session.start(for: 20, now: now)

        #expect(started)
        #expect(session == .timed(deadline: now.addingTimeInterval(20)))
    }

    @Test("extends from the existing deadline")
    func extensionUsesExistingDeadline() {
        var session = KeepAwakeSession.timed(deadline: now.addingTimeInterval(120))

        let extended = session.extend(by: 30)

        #expect(extended)
        #expect(session.deadline == now.addingTimeInterval(150))
    }

    @Test("repeated extensions accumulate exactly")
    func repeatedExtensionsAccumulate() {
        var session = KeepAwakeSession.timed(deadline: now)

        let extendedByThirty = session.extend(by: 30)
        let extendedByFortyFive = session.extend(by: 45)

        #expect(extendedByThirty)
        #expect(extendedByFortyFive)
        #expect(session.deadline == now.addingTimeInterval(75))
    }

    @Test("extension is a no-op for idle and indefinite sessions")
    func extensionOnlyAffectsTimedSessions() {
        var idle = KeepAwakeSession.idle
        var indefinite = KeepAwakeSession.indefinite

        #expect(idle.extend(by: 30) == false)
        #expect(indefinite.extend(by: 30) == false)
        #expect(idle == .idle)
        #expect(indefinite == .indefinite)
    }

    @Test("rejects invalid start durations without changing state")
    func invalidStartDurationsAreRejected() {
        for duration in [TimeInterval(0), -1, .nan, .infinity, -.infinity] {
            var session = KeepAwakeSession.idle

            #expect(session.start(for: duration, now: now) == false)
            #expect(session == .idle)
        }
    }

    @Test("rejects invalid extension durations without changing state")
    func invalidExtensionDurationsAreRejected() {
        for duration in [TimeInterval(0), -1, .nan, .infinity, -.infinity] {
            var session = KeepAwakeSession.timed(deadline: now.addingTimeInterval(60))
            let original = session

            let extended = session.extend(by: duration)

            #expect(extended == false)
            #expect(session == original)
        }
    }

    @Test("is active just before its deadline")
    func beforeDeadlineIsActive() {
        let session = KeepAwakeSession.timed(deadline: now)

        #expect(session.isExpired(at: now.addingTimeInterval(-0.001)) == false)
        #expect(session.remaining(at: now.addingTimeInterval(-0.001)) ?? 0 > 0)
    }

    @Test("expires at its exact deadline")
    func exactDeadlineExpires() {
        let session = KeepAwakeSession.timed(deadline: now)

        #expect(session.isExpired(at: now))
    }

    @Test("expires after its deadline")
    func afterDeadlineExpires() {
        let session = KeepAwakeSession.timed(deadline: now)

        #expect(session.isExpired(at: now.addingTimeInterval(1)))
    }

    @Test("expireIfNeeded transitions an expired session to idle")
    func expirationTransition() {
        var session = KeepAwakeSession.timed(deadline: now)

        let expired = session.expireIfNeeded(at: now)

        #expect(expired)
        #expect(session == .idle)
        let expiredAgain = session.expireIfNeeded(at: now)

        #expect(expiredAgain == false)
    }

    @Test("stop returns true for active sessions and becomes idle")
    func stopActiveSession() {
        var session = KeepAwakeSession.indefinite

        let stopped = session.stop()

        #expect(stopped)
        #expect(session == .idle)
    }

    @Test("repeated stop is false and remains idle")
    func repeatedStopIsIdempotent() {
        var session = KeepAwakeSession.idle

        let stopped = session.stop()
        let stoppedAgain = session.stop()

        #expect(stopped == false)
        #expect(stoppedAgain == false)
        #expect(session == .idle)
    }

    @Test("remaining time clamps to zero after the deadline")
    func remainingTimeClampsAtZero() {
        let session = KeepAwakeSession.timed(deadline: now)

        #expect(session.remaining(at: now.addingTimeInterval(1)) == 0)
    }
}
