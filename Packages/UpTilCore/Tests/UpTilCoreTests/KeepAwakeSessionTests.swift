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

    @Test("starts at an exact absolute deadline")
    func absoluteStartPreservesDeadline() {
        var session = KeepAwakeSession.idle
        let deadline = now.addingTimeInterval(90)

        let started = session.start(until: deadline, now: now)

        #expect(started)
        #expect(session == .timed(deadline: deadline))
    }

    @Test("absolute start replaces active states")
    func absoluteStartReplacesActiveState() {
        let deadline = now.addingTimeInterval(90)
        var timed = KeepAwakeSession.timed(deadline: now.addingTimeInterval(10))
        var indefinite = KeepAwakeSession.indefinite

        let timedStarted = timed.start(until: deadline, now: now)
        let indefiniteStarted = indefinite.start(until: deadline, now: now)

        #expect(timedStarted)
        #expect(indefiniteStarted)
        #expect(timed == .timed(deadline: deadline))
        #expect(indefinite == .timed(deadline: deadline))
    }

    @Test("rejects invalid absolute deadlines without changing state")
    func invalidAbsoluteDeadlinesAreRejected() {
        let invalidDates = [
            now,
            now.addingTimeInterval(-1),
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity),
        ]

        for deadline in invalidDates {
            var session = KeepAwakeSession.indefinite

            #expect(session.start(until: deadline, now: now) == false)
            #expect(session == .indefinite)
        }

        var session = KeepAwakeSession.indefinite
        let invalidNow = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(session.start(until: now.addingTimeInterval(1), now: invalidNow) == false)
        #expect(session == .indefinite)
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

    @Test("shortens from the existing deadline")
    func shorteningUsesExistingDeadline() {
        var session = KeepAwakeSession.timed(deadline: now.addingTimeInterval(120))

        #expect(session.canShorten(by: 30, at: now))
        let shortened = session.shorten(by: 30, at: now)

        #expect(shortened)
        #expect(session.deadline == now.addingTimeInterval(90))
    }

    @Test("repeated shortenings accumulate exactly")
    func repeatedShorteningsAccumulate() {
        var session = KeepAwakeSession.timed(deadline: now.addingTimeInterval(120))

        let shortenedByThirty = session.shorten(by: 30, at: now)
        let shortenedByFortyFive = session.shorten(by: 45, at: now)

        #expect(shortenedByThirty)
        #expect(shortenedByFortyFive)
        #expect(session.deadline == now.addingTimeInterval(45))
    }

    @Test("shortening requires a deadline strictly later than now")
    func shorteningRequiresRemainingTimeAboveDuration() {
        var strictlyAbove = KeepAwakeSession.timed(deadline: now.addingTimeInterval(30.001))
        var equal = KeepAwakeSession.timed(deadline: now.addingTimeInterval(30))
        var below = KeepAwakeSession.timed(deadline: now.addingTimeInterval(29.999))
        let equalOriginal = equal
        let belowOriginal = below

        #expect(strictlyAbove.canShorten(by: 30, at: now))
        let shortenedAbove = strictlyAbove.shorten(by: 30, at: now)
        let shortenedEqual = equal.shorten(by: 30, at: now)
        let shortenedBelow = below.shorten(by: 30, at: now)

        #expect(shortenedAbove)
        #expect(strictlyAbove.deadline == now.addingTimeInterval(0.001))
        #expect(!equal.canShorten(by: 30, at: now))
        #expect(!shortenedEqual)
        #expect(equal == equalOriginal)
        #expect(!below.canShorten(by: 30, at: now))
        #expect(!shortenedBelow)
        #expect(below == belowOriginal)
    }

    @Test("shortening is a no-op for idle and indefinite sessions")
    func shorteningOnlyAffectsTimedSessions() {
        var idle = KeepAwakeSession.idle
        var indefinite = KeepAwakeSession.indefinite

        #expect(!idle.canShorten(by: 30, at: now))
        let shortenedIdle = idle.shorten(by: 30, at: now)
        let shortenedIndefinite = indefinite.shorten(by: 30, at: now)

        #expect(!shortenedIdle)
        #expect(!indefinite.canShorten(by: 30, at: now))
        #expect(!shortenedIndefinite)
        #expect(idle == .idle)
        #expect(indefinite == .indefinite)
    }

    @Test("rejects invalid shortening inputs without changing state")
    func invalidShorteningInputsAreRejected() {
        let invalidDurations = [TimeInterval(0), -1, .nan, .infinity, -.infinity]

        for duration in invalidDurations {
            var session = KeepAwakeSession.timed(deadline: now.addingTimeInterval(60))
            let original = session

            #expect(!session.canShorten(by: duration, at: now))
            let shortened = session.shorten(by: duration, at: now)

            #expect(!shortened)
            #expect(session == original)
        }

        for invalidNow in [
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity),
        ] {
            var session = KeepAwakeSession.timed(deadline: now.addingTimeInterval(60))
            let original = session

            #expect(!session.canShorten(by: 30, at: invalidNow))
            let shortened = session.shorten(by: 30, at: invalidNow)

            #expect(!shortened)
            #expect(session == original)
        }

        let nanDeadline = Date(timeIntervalSinceReferenceDate: .nan)
        var nanSession = KeepAwakeSession.timed(deadline: nanDeadline)
        let originalNanBitPattern = nanDeadline.timeIntervalSinceReferenceDate.bitPattern

        #expect(!nanSession.canShorten(by: 30, at: now))
        let shortenedNan = nanSession.shorten(by: 30, at: now)

        #expect(!shortenedNan)
        if case let .timed(deadline) = nanSession {
            #expect(deadline.timeIntervalSinceReferenceDate.bitPattern == originalNanBitPattern)
        } else {
            Issue.record("NaN deadline session changed state")
        }

        for invalidDeadline in [
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity),
        ] {
            var session = KeepAwakeSession.timed(deadline: invalidDeadline)
            let original = session

            #expect(!session.canShorten(by: 30, at: now))
            let shortened = session.shorten(by: 30, at: now)

            #expect(!shortened)
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

extension KeepAwakeSessionTests {
    @Test("pause freezes the exact remaining time and releases activity")
    func pauseFreezesRemainingTime() {
        var session = KeepAwakeSession.timed(deadline: now.addingTimeInterval(90.25))

        let paused = session.pause(at: now)
        let expired = session.expireIfNeeded(at: now.addingTimeInterval(3600))

        #expect(paused)
        #expect(!expired)
        #expect(session == .paused(remaining: 90.25))
        #expect(session.isPaused)
        #expect(!session.isActive)
        #expect(session.deadline == nil)
        #expect(session.remaining(at: now.addingTimeInterval(3600)) == 90.25)
        #expect(!session.isExpired(at: now.addingTimeInterval(3600)))
    }

    @Test("resume continues from the saved time, so the deadline moves later")
    func resumeMovesDeadlineLater() {
        var session = KeepAwakeSession.paused(remaining: 90.25)
        let resumedAt = now.addingTimeInterval(3600)

        let resumed = session.resume(at: resumedAt)

        #expect(resumed)
        #expect(session == .timed(deadline: resumedAt.addingTimeInterval(90.25)))
        #expect(!session.isExpired(at: resumedAt.addingTimeInterval(90)))
        #expect(session.isExpired(at: resumedAt.addingTimeInterval(90.25)))
    }

    @Test("repeated pause and resume cycles keep fractional seconds")
    func pauseResumeCyclesKeepFractions() {
        var session = KeepAwakeSession.idle

        let started = session.start(for: 100.5, now: now)
        let firstPause = session.pause(at: now.addingTimeInterval(10.25))
        let firstSaved = session
        let firstResume = session.resume(at: now.addingTimeInterval(1000))
        let secondPause = session.pause(at: now.addingTimeInterval(1030.125))
        let secondSaved = session
        let secondResume = session.resume(at: now.addingTimeInterval(5000))

        #expect(started && firstPause && firstResume && secondPause && secondResume)
        #expect(firstSaved == .paused(remaining: 90.25))
        #expect(secondSaved == .paused(remaining: 60.125))
        #expect(session == .timed(deadline: now.addingTimeInterval(5060.125)))
    }

    @Test("pause rejects other states, ended timers, and invalid times without changing state")
    func invalidPausesAreRejected() {
        let deadline = now.addingTimeInterval(60)
        for original in [KeepAwakeSession.idle, .indefinite, .paused(remaining: 30)] {
            var session = original
            let paused = session.pause(at: now)
            #expect(!paused)
            #expect(session == original)
        }
        for date in [deadline, deadline.addingTimeInterval(1), Date(timeIntervalSinceReferenceDate: .nan)] {
            var session = KeepAwakeSession.timed(deadline: deadline)
            let paused = session.pause(at: date)
            #expect(!paused)
            #expect(session == .timed(deadline: deadline))
        }
    }

    @Test("resume rejects other states and invalid saved or resulting deadlines")
    func invalidResumesAreRejected() {
        for original in [KeepAwakeSession.idle, .indefinite, .timed(deadline: now.addingTimeInterval(60))] {
            var session = original
            let resumed = session.resume(at: now)
            #expect(!resumed)
            #expect(session == original)
        }
        for remaining in [0, -1, TimeInterval.infinity, 1e-300] {
            var session = KeepAwakeSession.paused(remaining: remaining)
            let resumed = session.resume(at: now)
            #expect(!resumed)
            #expect(session == .paused(remaining: remaining))
        }
        var notANumber = KeepAwakeSession.paused(remaining: .nan)
        var invalidNow = KeepAwakeSession.paused(remaining: 60)
        var overflowing = KeepAwakeSession.paused(remaining: .greatestFiniteMagnitude)

        let notANumberResumed = notANumber.resume(at: now)
        let invalidNowResumed = invalidNow.resume(at: Date(timeIntervalSinceReferenceDate: .nan))
        let overflowingResumed = overflowing.resume(at: Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude))

        #expect(!notANumberResumed)
        #expect(notANumber.remaining(at: now)?.isNaN == true)
        #expect(!invalidNowResumed)
        #expect(invalidNow == .paused(remaining: 60))
        #expect(!overflowingResumed)
        #expect(overflowing == .paused(remaining: .greatestFiniteMagnitude))
    }

    @Test("stop discards a paused session")
    func stopDiscardsPausedSession() {
        var session = KeepAwakeSession.paused(remaining: 30)

        let stopped = session.stop()
        let stoppedAgain = session.stop()

        #expect(stopped)
        #expect(!stoppedAgain)
        #expect(session == .idle)
    }

    @Test("paused sessions reject adjustments and invalid starts")
    func pausedSessionRejectsAdjustments() {
        let paused = KeepAwakeSession.paused(remaining: 30)
        var session = paused

        let extended = session.extend(by: 60)
        let shortened = session.shorten(by: 10, at: now)
        let zeroStart = session.start(for: 0, now: now)
        let staleStart = session.start(until: now, now: now)

        #expect(!extended)
        #expect(!session.canShorten(by: 10, at: now))
        #expect(!shortened)
        #expect(!zeroStart)
        #expect(!staleStart)
        #expect(session == paused)
    }

    @Test("valid starts replace a paused session")
    func validStartsReplacePausedSession() {
        var timed = KeepAwakeSession.paused(remaining: 30)
        var absolute = KeepAwakeSession.paused(remaining: 30)
        var indefinite = KeepAwakeSession.paused(remaining: 30)

        let timedStarted = timed.start(for: 60, now: now)
        let absoluteStarted = absolute.start(until: now.addingTimeInterval(90), now: now)
        indefinite.startIndefinitely()

        #expect(timedStarted)
        #expect(absoluteStarted)
        #expect(timed == .timed(deadline: now.addingTimeInterval(60)))
        #expect(absolute == .timed(deadline: now.addingTimeInterval(90)))
        #expect(indefinite == .indefinite)
    }
}
