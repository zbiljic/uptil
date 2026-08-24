import Foundation
import Testing
@testable import UpTil

@MainActor
@Suite("ProcessInfo keep-awake service")
struct KeepAwakeServiceTests {
    @Test("base activation requests only the system assertion once")
    func baseActivationIsIdempotent() {
        var requests: [(ProcessInfo.ActivityOptions, String)] = []
        let service = ProcessInfoKeepAwakeService(
            beginActivity: { options, reason in
                requests.append((options, reason))
                return NSObject()
            },
            endActivity: { _ in }
        )

        service.activate()
        service.activate()

        #expect(service.isActive)
        #expect(!service.isDisplaySleepPreventionActive)
        #expect(requests.count == 1)
        #expect(requests.first?.0 == [.idleSystemSleepDisabled])
        #expect(requests.first?.1 == "UpTil keep-awake session")
    }

    @Test("display prevention cannot activate while idle")
    func displayEnableWhileIdleDoesNothing() {
        var beginCount = 0
        let service = ProcessInfoKeepAwakeService(
            beginActivity: { _, _ in
                beginCount += 1
                return NSObject()
            },
            endActivity: { _ in }
        )

        service.setDisplaySleepPreventionEnabled(true)

        #expect(beginCount == 0)
        #expect(!service.isActive)
        #expect(!service.isDisplaySleepPreventionActive)
    }

    @Test("active display enable requests its independent assertion once")
    func displayEnableIsIndependentAndIdempotent() {
        var requests: [(ProcessInfo.ActivityOptions, String)] = []
        let service = ProcessInfoKeepAwakeService(
            beginActivity: { options, reason in
                requests.append((options, reason))
                return NSObject()
            },
            endActivity: { _ in }
        )

        service.activate()
        service.setDisplaySleepPreventionEnabled(true)
        service.setDisplaySleepPreventionEnabled(true)

        #expect(service.isActive)
        #expect(service.isDisplaySleepPreventionActive)
        #expect(requests.count == 2)
        #expect(requests[1].0 == [.idleDisplaySleepDisabled])
        #expect(requests[1].1 == "UpTil display-awake option")
    }

    @Test("display disable ends only the display token")
    func displayDisableLeavesBaseActive() {
        let systemToken = NSObject()
        let displayToken = NSObject()
        var endedTokens: [NSObjectProtocol] = []
        let service = ProcessInfoKeepAwakeService(
            beginActivity: { options, _ in
                options == [.idleSystemSleepDisabled] ? systemToken : displayToken
            },
            endActivity: { token in
                endedTokens.append(token)
            }
        )

        service.activate()
        service.setDisplaySleepPreventionEnabled(true)
        service.setDisplaySleepPreventionEnabled(false)
        service.setDisplaySleepPreventionEnabled(false)

        #expect(service.isActive)
        #expect(!service.isDisplaySleepPreventionActive)
        #expect(endedTokens.count == 1)
        #expect(endedTokens[0] === displayToken)
    }

    @Test("full deactivation ends each exact token once")
    func fullDeactivationEndsBothTokensOnce() {
        let systemToken = NSObject()
        let displayToken = NSObject()
        var endedTokens: [NSObjectProtocol] = []
        let service = ProcessInfoKeepAwakeService(
            beginActivity: { options, _ in
                options == [.idleSystemSleepDisabled] ? systemToken : displayToken
            },
            endActivity: { token in
                endedTokens.append(token)
            }
        )

        service.activate()
        service.setDisplaySleepPreventionEnabled(true)
        service.deactivate()
        service.deactivate()

        #expect(!service.isActive)
        #expect(!service.isDisplaySleepPreventionActive)
        #expect(endedTokens.count == 2)
        #expect(endedTokens[0] === displayToken)
        #expect(endedTokens[1] === systemToken)
    }
}

@MainActor
@Suite("Display-awake controller policy")
struct DisplayAwakeControllerTests {
    private let startDate = Date(timeIntervalSinceReferenceDate: 1000)

    @Test("preference adapter defaults false and persists Boolean writes")
    func preferenceAdapterPersistsInIsolatedDefaults() throws {
        let suiteName = "com.zbiljic.uptil.tests.display-sleep.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preference = UserDefaultsDisplaySleepPreference(defaults: defaults)
        #expect(!preference.isEnabled)
        preference.isEnabled = true
        #expect(UserDefaultsDisplaySleepPreference(defaults: defaults).isEnabled)
        preference.isEnabled = false
        #expect(!UserDefaultsDisplaySleepPreference(defaults: defaults).isEnabled)
    }

    @Test("enabling while idle persists without acquiring an assertion")
    func idlePreferenceChangeDoesNotAssert() {
        let fixture = makeController()

        fixture.controller.setKeepsDisplayAwake(true)

        #expect(fixture.controller.keepsDisplayAwake)
        #expect(fixture.preference.writes == [true])
        #expect(fixture.service.activationCount == 0)
        #expect(fixture.service.displayEnableCount == 0)
    }

    @Test("stored display preference applies to every session start form")
    func storedPreferenceAppliesToAllStartForms() {
        let timed = makeController(keepsDisplayAwake: true)
        #expect(timed.controller.start(for: 60))
        let until = makeController(keepsDisplayAwake: true)
        #expect(until.controller.start(until: startDate.addingTimeInterval(60)))
        let indefinite = makeController(keepsDisplayAwake: true)
        indefinite.controller.startIndefinitely()

        for fixture in [timed, until, indefinite] {
            #expect(fixture.service.activationCount == 1)
            #expect(fixture.service.displayEnableCount == 1)
            #expect(fixture.service.isActive)
            #expect(fixture.service.isDisplaySleepPreventionActive)
        }
    }

    @Test("enabling during timed and indefinite sessions activates display only")
    func activePreferenceEnableIsImmediate() {
        let timed = makeController()
        #expect(timed.controller.start(for: 60))
        timed.controller.setKeepsDisplayAwake(true)
        let indefinite = makeController()
        indefinite.controller.startIndefinitely()
        indefinite.controller.setKeepsDisplayAwake(true)

        for fixture in [timed, indefinite] {
            #expect(fixture.service.activationCount == 1)
            #expect(fixture.service.displayEnableCount == 1)
            #expect(fixture.service.isActive)
            #expect(fixture.service.isDisplaySleepPreventionActive)
        }
    }

    @Test("disabling during a session leaves the base assertion active")
    func activePreferenceDisableLeavesBaseActive() {
        let fixture = makeController(keepsDisplayAwake: true)
        fixture.controller.startIndefinitely()

        fixture.controller.setKeepsDisplayAwake(false)

        #expect(fixture.service.isActive)
        #expect(!fixture.service.isDisplaySleepPreventionActive)
        #expect(fixture.service.deactivationCount == 0)
        #expect(fixture.service.displayDisableCount == 1)
        #expect(fixture.preference.writes == [false])
    }

    @Test("repeating a preference value neither writes nor reacquires")
    func repeatedPreferenceValueDoesNothing() {
        let fixture = makeController(keepsDisplayAwake: true)
        fixture.controller.startIndefinitely()

        fixture.controller.setKeepsDisplayAwake(true)
        fixture.controller.setKeepsDisplayAwake(true)

        #expect(fixture.preference.writes.isEmpty)
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.displayEnableCount == 1)
    }

    @Test("session adjustments and replacements preserve one display assertion")
    func activeSessionChangesDoNotDuplicateAssertions() {
        let fixture = makeController(keepsDisplayAwake: true)

        #expect(fixture.controller.start(for: 120))
        #expect(fixture.controller.extend(by: 30))
        #expect(fixture.controller.shorten(by: 15))
        fixture.controller.startIndefinitely()
        #expect(fixture.controller.start(for: 60))
        #expect(fixture.controller.start(until: startDate.addingTimeInterval(90)))

        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.displayEnableCount == 1)
        #expect(fixture.service.displayDisableCount == 0)
    }

    @Test("stop releases both assertions and preserves the preference")
    func stopReleasesBothAndPreservesPreference() {
        let fixture = makeController(keepsDisplayAwake: true)
        #expect(fixture.controller.start(for: 60))

        fixture.controller.stop()

        #expect(!fixture.service.isActive)
        #expect(!fixture.service.isDisplaySleepPreventionActive)
        #expect(fixture.service.deactivationCount == 1)
        #expect(fixture.service.displayDisableCount == 1)
        #expect(fixture.controller.keepsDisplayAwake)
        #expect(fixture.preference.writes.isEmpty)
    }

    @Test("exact and overdue expiry release display while preserving preference")
    func expiryReleasesDisplayAndPreservesPreference() {
        for elapsed in [10.0, 11.0] {
            let fixture = makeController(keepsDisplayAwake: true)
            #expect(fixture.controller.start(for: 10))
            fixture.clock.currentDate = startDate.addingTimeInterval(elapsed)

            #expect(fixture.controller.expireIfNeeded(at: fixture.clock.currentDate))
            #expect(fixture.service.deactivationCount == 1)
            #expect(fixture.service.displayDisableCount == 1)
            #expect(fixture.controller.keepsDisplayAwake)
        }
    }

    @Test("shutdown cleanup is idempotent for both assertions")
    func shutdownCleansBothAssertionsOnce() {
        let fixture = makeController(keepsDisplayAwake: true)
        fixture.controller.startIndefinitely()

        fixture.controller.shutdown()
        fixture.controller.shutdown()

        #expect(fixture.service.deactivationCount == 1)
        #expect(fixture.service.displayDisableCount == 1)
        #expect(fixture.controller.keepsDisplayAwake)
    }

    @Test("controller loads true preference without asserting while idle")
    func initialTruePreferenceIsIdleConfiguration() {
        let fixture = makeController(keepsDisplayAwake: true)

        #expect(fixture.controller.keepsDisplayAwake)
        #expect(!fixture.service.isActive)
        #expect(!fixture.service.isDisplaySleepPreventionActive)
        #expect(fixture.preference.writes.isEmpty)
    }

    private func makeController(keepsDisplayAwake: Bool = false) -> SessionControllerFixture {
        SessionControllerFixture(
            startDate: startDate,
            keepsDisplayAwake: keepsDisplayAwake
        )
    }
}
