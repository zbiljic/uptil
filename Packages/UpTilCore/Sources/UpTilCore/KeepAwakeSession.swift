import Foundation

public enum KeepAwakeSession: Equatable, Sendable {
    case idle
    case timed(deadline: Date)
    case indefinite
    /// A timed session with its countdown frozen. Sleep prevention is released until it resumes.
    case paused(remaining: TimeInterval)

    public var isActive: Bool {
        switch self {
        case .idle, .paused:
            false
        case .timed, .indefinite:
            true
        }
    }

    public var isPaused: Bool {
        if case .paused = self {
            return true
        }
        return false
    }

    public var deadline: Date? {
        switch self {
        case .idle, .indefinite, .paused:
            nil
        case let .timed(deadline):
            deadline
        }
    }

    public func remaining(at now: Date) -> TimeInterval? {
        switch self {
        case .idle, .indefinite:
            nil
        case let .timed(deadline):
            max(0, deadline.timeIntervalSince(now))
        case let .paused(remaining):
            remaining
        }
    }

    public func isExpired(at now: Date) -> Bool {
        switch self {
        case .idle, .indefinite, .paused:
            false
        case let .timed(deadline):
            now >= deadline
        }
    }

    @discardableResult
    public mutating func start(for duration: TimeInterval, now: Date) -> Bool {
        guard duration.isFinite, duration > 0 else {
            return false
        }

        self = .timed(deadline: now.addingTimeInterval(duration))
        return true
    }

    @discardableResult
    public mutating func start(until deadline: Date, now: Date) -> Bool {
        guard
            now.timeIntervalSinceReferenceDate.isFinite,
            deadline.timeIntervalSinceReferenceDate.isFinite,
            deadline > now
        else {
            return false
        }

        self = .timed(deadline: deadline)
        return true
    }

    public mutating func startIndefinitely() {
        self = .indefinite
    }

    @discardableResult
    public mutating func extend(by duration: TimeInterval) -> Bool {
        guard duration.isFinite, duration > 0 else {
            return false
        }

        switch self {
        case .idle, .indefinite, .paused:
            return false
        case let .timed(deadline):
            self = .timed(deadline: deadline.addingTimeInterval(duration))
            return true
        }
    }

    public func canShorten(by duration: TimeInterval, at now: Date) -> Bool {
        guard
            duration.isFinite,
            duration > 0,
            now.timeIntervalSinceReferenceDate.isFinite
        else {
            return false
        }

        switch self {
        case .idle, .indefinite, .paused:
            return false
        case let .timed(deadline):
            let shortenedDeadline = deadline.addingTimeInterval(-duration)
            return deadline.timeIntervalSinceReferenceDate.isFinite
                && shortenedDeadline.timeIntervalSinceReferenceDate.isFinite
                && shortenedDeadline > now
        }
    }

    @discardableResult
    public mutating func shorten(by duration: TimeInterval, at now: Date) -> Bool {
        guard canShorten(by: duration, at: now), case let .timed(deadline) = self else {
            return false
        }

        self = .timed(deadline: deadline.addingTimeInterval(-duration))
        return true
    }

    /// Freezes an unexpired timed session's exact remaining time.
    @discardableResult
    public mutating func pause(at now: Date) -> Bool {
        guard now.timeIntervalSinceReferenceDate.isFinite, case let .timed(deadline) = self else {
            return false
        }

        let remaining = deadline.timeIntervalSince(now)
        guard remaining.isFinite, remaining > 0 else {
            return false
        }

        self = .paused(remaining: remaining)
        return true
    }

    /// Continues a paused session from its saved remaining time, so the deadline moves later.
    @discardableResult
    public mutating func resume(at now: Date) -> Bool {
        guard
            now.timeIntervalSinceReferenceDate.isFinite,
            case let .paused(remaining) = self,
            remaining.isFinite,
            remaining > 0
        else {
            return false
        }

        let deadline = now.addingTimeInterval(remaining)
        guard deadline.timeIntervalSinceReferenceDate.isFinite, deadline > now else {
            return false
        }

        self = .timed(deadline: deadline)
        return true
    }

    @discardableResult
    public mutating func expireIfNeeded(at now: Date) -> Bool {
        guard isExpired(at: now) else {
            return false
        }

        self = .idle
        return true
    }

    @discardableResult
    public mutating func stop() -> Bool {
        guard self != .idle else {
            return false
        }

        self = .idle
        return true
    }
}
