import Foundation

/// The end time the idle Until picker offers. Untouched, it follows the clock; a time the user
/// picks holds until it passes, or until the popover stays closed long enough to forget it.
public struct UntilSelection: Equatable, Sendable {
    /// How far ahead the suggestion starts before it rounds up to the quarter hour.
    public static let suggestionLead: TimeInterval = 45 * 60
    /// How long the popover must stay closed before a picked time is forgotten.
    public static let pickLifetimeWhileClosed: TimeInterval = 10 * 60
    private static let quarterHour: TimeInterval = 15 * 60

    private var pickedDeadline: Date?
    private var closedSince: Date?

    public init() {}

    /// The deadline the picker shows and Start submits.
    public func deadline(at now: Date, calendar: Calendar) -> Date? {
        if let pickedDeadline, now < pickedDeadline {
            return pickedDeadline
        }

        return Self.suggestedDeadline(after: now, calendar: calendar)
    }

    /// Holds the next occurrence of the picked clock time. Committing the time already shown
    /// is not a choice, so an untouched suggestion keeps following the clock.
    public mutating func pick(_ time: Date, at now: Date, calendar: Calendar) {
        let shown = deadline(at: now, calendar: calendar).map { calendar.dateComponents([.hour, .minute], from: $0) }
        guard shown != calendar.dateComponents([.hour, .minute], from: time) else {
            return
        }

        pickedDeadline = WallClockDeadline.nextOccurrence(of: time, after: now, calendar: calendar)
    }

    /// Repeated close notices keep the first close time.
    public mutating func popoverDidClose(at now: Date) {
        if closedSince == nil {
            closedSince = now
        }
    }

    public mutating func popoverDidOpen(at now: Date) {
        if let closedSince, now.timeIntervalSince(closedSince) >= Self.pickLifetimeWhileClosed {
            pickedDeadline = nil
        }
        closedSince = nil
    }

    /// Rounds the lead up to the quarter hour, so the suggestion is always 45–59 minutes away.
    /// It is an absolute instant, so a repeated hour at a clock change cannot push it to tomorrow.
    private static func suggestedDeadline(after now: Date, calendar: Calendar) -> Date? {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            return nil
        }

        let earliest = now.addingTimeInterval(suggestionLead)
        guard let hour = calendar.dateInterval(of: .hour, for: earliest) else {
            return nil
        }

        let quarters = (earliest.timeIntervalSince(hour.start) / quarterHour).rounded(.up)
        return hour.start.addingTimeInterval(quarters * quarterHour)
    }
}
