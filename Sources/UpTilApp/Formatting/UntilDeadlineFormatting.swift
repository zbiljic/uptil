import Foundation
import UpTilCore

enum UntilDeadlineFormatting {
    /// From this length on, the preview stands out: a time picked long ago can mean a day-long session.
    static let longSession: TimeInterval = 12 * 60 * 60

    static func string(
        for deadline: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        // Same phrasing as the running countdown's "remaining · ends today at 20:16".
        let endTime = EndTimeFormatting.string(
            for: deadline,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let length = CompactDurationFormatter.string(remaining: deadline.timeIntervalSince(now))
        return "Ends \(endTime) · \(length)"
    }

    static func isLongSession(ending deadline: Date, now: Date) -> Bool {
        deadline.timeIntervalSince(now) >= longSession
    }
}
