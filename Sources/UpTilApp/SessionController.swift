import Foundation
import Observation
import UpTilCore

@MainActor
@Observable
final class SessionController {
    private(set) var session: KeepAwakeSession = .idle

    private let keepAwakeService: any KeepAwakeManaging
    private let expiryScheduler: any ExpiryScheduling
    private let now: @MainActor () -> Date
    private var expiryCancellation: (any ExpiryCancellation)?

    var assertionIsActive: Bool {
        keepAwakeService.isActive
    }

    init(
        keepAwakeService: any KeepAwakeManaging = ProcessInfoKeepAwakeService(),
        expiryScheduler: any ExpiryScheduling = TaskExpiryScheduler(),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.keepAwakeService = keepAwakeService
        self.expiryScheduler = expiryScheduler
        self.now = now
    }

    @discardableResult
    func start(for duration: TimeInterval) -> Bool {
        let wasIdle = !session.isActive
        guard session.start(for: duration, now: now()) else {
            return false
        }

        if wasIdle {
            keepAwakeService.activate()
        }
        scheduleExpiry()
        return true
    }

    @discardableResult
    func start(until deadline: Date) -> Bool {
        let wasIdle = !session.isActive
        guard session.start(until: deadline, now: now()) else {
            return false
        }

        if wasIdle {
            keepAwakeService.activate()
        }
        scheduleExpiry()
        return true
    }

    func startIndefinitely() {
        let wasIdle = !session.isActive
        session.startIndefinitely()
        cancelScheduledExpiry()

        if wasIdle {
            keepAwakeService.activate()
        }
    }

    @discardableResult
    func extend(by duration: TimeInterval) -> Bool {
        guard session.extend(by: duration) else {
            return false
        }

        scheduleExpiry()
        return true
    }

    @discardableResult
    func shorten(by duration: TimeInterval) -> Bool {
        guard session.shorten(by: duration, at: now()) else {
            return false
        }

        scheduleExpiry()
        return true
    }

    @discardableResult
    func refresh(at date: Date) -> Bool {
        expireIfNeeded(at: date)
    }

    @discardableResult
    func expireIfNeeded(at date: Date) -> Bool {
        guard session.expireIfNeeded(at: date) else {
            return false
        }

        cancelScheduledExpiry()
        keepAwakeService.deactivate()
        return true
    }

    func stop() {
        guard session.stop() else {
            return
        }

        cancelScheduledExpiry()
        keepAwakeService.deactivate()
    }

    func shutdown() {
        stop()
    }

    private func scheduleExpiry() {
        cancelScheduledExpiry()

        guard let deadline = session.deadline else {
            return
        }

        expiryCancellation = expiryScheduler.schedule(at: deadline) { [weak self] in
            self?.handleScheduledExpiry()
        }
    }

    private func cancelScheduledExpiry() {
        expiryCancellation?.cancel()
        expiryCancellation = nil
    }

    private func handleScheduledExpiry() {
        let currentTime = now()
        if expireIfNeeded(at: currentTime) {
            return
        }

        // A stale/early callback or a wall-clock adjustment needs a fresh,
        // deadline-based one-shot timer for the current session state.
        scheduleExpiry()
    }
}
