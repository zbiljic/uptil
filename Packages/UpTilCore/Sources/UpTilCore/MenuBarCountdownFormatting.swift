import Foundation

/// Formats the minute-resolution countdown shown in the menu bar.
public enum MenuBarCountdownFormatting {
    private static let secondsPerMinute = 60.0
    private static let secondsPerHour = 60.0 * secondsPerMinute
    private static let ninetyMinutes = 90.0 * secondsPerMinute
    private static let boundaryTolerance = 0.01

    /// Returns a compact countdown surrounded by inward mathematical angles.
    ///
    /// Between 60 and 90 minutes the display uses hours and remaining
    /// minutes; at 90 minutes and above it rounds up to whole hours.
    /// Non-positive and non-finite values defensively display one minute.
    public static func string(remaining: TimeInterval) -> String {
        "⟩\(durationString(remaining: remaining))⟨"
    }

    /// Returns the countdown value without its visual delimiters.
    public static func durationString(remaining: TimeInterval) -> String {
        guard remaining.isFinite, remaining > 0 else {
            return "1m"
        }

        if remaining < secondsPerMinute {
            return "\(ceilingInteger(remaining / secondsPerMinute))m"
        }

        if remaining < secondsPerHour {
            return "\(ceilingInteger(remaining / secondsPerMinute))m"
        }

        if remaining < ninetyMinutes {
            let remainingMinutes = ceilingInteger((remaining - secondsPerHour) / secondsPerMinute)
            if remainingMinutes == 0 {
                return "1h"
            }

            return "1h\(remainingMinutes)m"
        }

        return "\(ceilingInteger(remaining / secondsPerHour))h"
    }

    /// Returns a positive delay until the next possible display change.
    ///
    /// The caller should recalculate the remaining time after sleeping. A
    /// small tolerance carries the calculation beyond exact boundaries and
    /// prevents an exact-boundary value from creating a zero-delay loop.
    public static func nextRefreshDelay(remaining: TimeInterval) -> TimeInterval {
        guard remaining.isFinite, remaining > 0 else {
            return secondsPerMinute
        }

        if remaining < ninetyMinutes {
            if remaining >= secondsPerHour {
                let distanceFromHour = remaining - secondsPerHour
                if distanceFromHour <= boundaryTolerance {
                    return max(boundaryTolerance, distanceFromHour + boundaryTolerance)
                }
            }

            let minuteRemainder = remaining.truncatingRemainder(dividingBy: secondsPerMinute)
            let boundaryDistance = minuteRemainder > 0
                ? minuteRemainder
                : secondsPerMinute
            return boundaryDistance + boundaryTolerance
        }

        let displayedHours = ceil(remaining / secondsPerHour)
        guard displayedHours < Double(Int.max) else {
            return secondsPerHour
        }

        let nextBucketBoundary = max(
            ninetyMinutes,
            (displayedHours - 1) * secondsPerHour
        )
        return max(
            boundaryTolerance,
            remaining - nextBucketBoundary + boundaryTolerance
        )
    }

    private static func ceilingInteger(_ value: TimeInterval) -> Int {
        let maximum = Double(Int.max)
        return Int(min(maximum, ceil(value)))
    }
}
