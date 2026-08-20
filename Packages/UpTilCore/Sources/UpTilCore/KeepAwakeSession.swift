import Foundation

public enum KeepAwakeSession: Equatable, Sendable {
    case idle
    case timed(deadline: Date)
    case indefinite

    public var isActive: Bool {
        switch self {
        case .idle:
            false
        case .timed, .indefinite:
            true
        }
    }

    public var deadline: Date? {
        switch self {
        case .idle, .indefinite:
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
        }
    }

    public func isExpired(at now: Date) -> Bool {
        switch self {
        case .idle, .indefinite:
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
        case .idle, .indefinite:
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
        case .idle, .indefinite:
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
        guard isActive else {
            return false
        }

        self = .idle
        return true
    }
}
