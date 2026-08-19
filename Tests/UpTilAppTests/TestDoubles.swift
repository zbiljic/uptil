import Foundation
@testable import UpTil

@MainActor
final class FakeKeepAwakeService: KeepAwakeManaging {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    private(set) var isActive = false

    func activate() {
        guard !isActive else {
            return
        }

        isActive = true
        activationCount += 1
    }

    func deactivate() {
        guard isActive else {
            return
        }

        isActive = false
        deactivationCount += 1
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
