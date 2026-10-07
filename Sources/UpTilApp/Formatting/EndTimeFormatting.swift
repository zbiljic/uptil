import Foundation

enum EndTimeFormatting {
    static func string(
        for deadline: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let deadlineDay = calendar.startOfDay(for: deadline)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short

        if deadlineDay == today {
            return "today at \(formatter.string(from: deadline))"
        }
        if deadlineDay == calendar.date(byAdding: .day, value: 1, to: today) {
            return "tomorrow at \(formatter.string(from: deadline))"
        }

        formatter.dateStyle = .short
        return formatter.string(from: deadline)
    }
}
