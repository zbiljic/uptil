import Foundation
@testable import UpTil

@MainActor
final class FakeKeepAwakeService: KeepAwakeManaging {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    private(set) var displayEnableCount = 0
    private(set) var displayDisableCount = 0
    private(set) var isActive = false
    private(set) var isDisplaySleepPreventionActive = false

    func activate() {
        guard !isActive else {
            return
        }

        isActive = true
        activationCount += 1
    }

    func setDisplaySleepPreventionEnabled(_ enabled: Bool) {
        if enabled {
            guard isActive, !isDisplaySleepPreventionActive else {
                return
            }

            isDisplaySleepPreventionActive = true
            displayEnableCount += 1
            return
        }

        guard isDisplaySleepPreventionActive else {
            return
        }

        isDisplaySleepPreventionActive = false
        displayDisableCount += 1
    }

    func deactivate() {
        guard isActive else {
            return
        }

        if isDisplaySleepPreventionActive {
            isDisplaySleepPreventionActive = false
            displayDisableCount += 1
        }
        isActive = false
        deactivationCount += 1
    }
}

@MainActor
final class FakeDisplaySleepPreference: DisplaySleepPreferenceManaging {
    private(set) var writes: [Bool] = []
    var isEnabled: Bool {
        didSet {
            writes.append(isEnabled)
        }
    }

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

@MainActor
final class ManualExpiryScheduler: ExpiryScheduling {
    private(set) var scheduledDeadlines: [Date] = []
    private(set) var cancellationCount = 0
    private var actions: [@MainActor () -> Void] = []

    func schedule(
        at deadline: Date,
        action: @escaping @MainActor () -> Void
    ) -> any ExpiryCancellation {
        scheduledDeadlines.append(deadline)
        actions.append(action)

        return ManualExpiryCancellation { [weak self] in
            self?.cancellationCount += 1
        }
    }

    func fireScheduled(at index: Int) {
        actions[index]()
    }
}

@MainActor
private final class ManualExpiryCancellation: ExpiryCancellation {
    private var onCancel: (@MainActor () -> Void)?

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard let onCancel else {
            return
        }

        self.onCancel = nil
        onCancel()
    }
}

@MainActor
final class TestClock {
    var currentDate: Date

    init(_ currentDate: Date) {
        self.currentDate = currentDate
    }
}
