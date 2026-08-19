import Foundation

enum UntilDeadlineFormatting {
    static func string(
        for deadline: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone

        let today = calendar.startOfDay(for: now)
        let deadlineDay = calendar.startOfDay(for: deadline)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)

        let dayDescription = if deadlineDay == today {
            "Today"
        } else if deadlineDay == tomorrow {
            "Tomorrow"
        } else {
            "Unexpected date"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(dayDescription), \(formatter.string(from: deadline))"
    }
}
