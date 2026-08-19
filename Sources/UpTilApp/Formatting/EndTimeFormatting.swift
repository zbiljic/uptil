import Foundation

enum EndTimeFormatting {
    static func string(
        for deadline: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "UpTil \(formatter.string(from: deadline))"
    }
}
