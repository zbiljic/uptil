import Foundation

public enum CompactDurationFormatter {
    private static let secondsPerMinute = 60.0
    private static let secondsPerHour = 3600.0

    public static func string(remaining: TimeInterval) -> String {
        guard remaining.isFinite, remaining > 0 else {
            return "0m"
        }

        guard remaining >= secondsPerMinute else {
            return "<1m"
        }

        let roundedMinutes = ceil(remaining / secondsPerMinute)
        // Keep the conversion below Int.max even for very large finite values.
        let maximumMinutes = Double(Int.max / 60)
        let totalMinutes = Int(min(roundedMinutes, maximumMinutes))

        // Before a full hour, retain minute notation: 59m 1s is 60m.
        guard remaining >= secondsPerHour else {
            return "\(totalMinutes)m"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}
