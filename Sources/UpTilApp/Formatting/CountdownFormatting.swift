import Foundation

/// The popover's large countdown keeps one width below ten hours: a zero hour is shown
/// faded instead of dropped, so a click across the hour never re-centers the number.
enum CountdownFormatting {
    struct Parts: Equatable {
        let fadedPrefix: String
        let value: String
    }

    static func parts(remaining: TimeInterval) -> Parts {
        let total = wholeSeconds(remaining)
        let hours = total / 3600
        let minutesAndSeconds = String(format: "%02d:%02d", total % 3600 / 60, total % 60)

        if hours == 0 {
            return Parts(fadedPrefix: "0:", value: minutesAndSeconds)
        }
        return Parts(fadedPrefix: "", value: "\(hours):\(minutesAndSeconds)")
    }

    static func accessibilityDuration(
        remaining: TimeInterval,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        Duration.seconds(wholeSeconds(remaining))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale))
    }

    /// Rounds up like a timer, so the display reaches zero exactly at the deadline.
    private static func wholeSeconds(_ remaining: TimeInterval) -> Int {
        guard remaining.isFinite, remaining > 0 else {
            return 0
        }

        // Keep the conversion below Int.max even for very large finite values.
        return Int(min(remaining.rounded(.up), Double(Int.max / 2)))
    }
}
