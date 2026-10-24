import Foundation

enum UntilDeadlineFormatting {
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
        return "Ends \(endTime)"
    }
}
