import Foundation

@MainActor
protocol ExpiryCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol ExpiryScheduling: AnyObject {
    func schedule(
        at deadline: Date,
        action: @escaping @MainActor () -> Void
    ) -> any ExpiryCancellation
}

@MainActor
final class TaskExpiryScheduler: ExpiryScheduling {
    private let now: @MainActor () -> Date

    init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    func schedule(
        at deadline: Date,
        action: @escaping @MainActor () -> Void
    ) -> any ExpiryCancellation {
        let delay = max(0, deadline.timeIntervalSince(now()))
        let task = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }

            guard !Task.isCancelled else {
                return
            }

            action()
        }

        return TaskExpiryCancellation(task: task)
    }
}

@MainActor
private final class TaskExpiryCancellation: ExpiryCancellation {
    private var task: Task<Void, Never>?

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
