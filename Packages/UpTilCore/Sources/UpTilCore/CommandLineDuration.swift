import Foundation

public enum CommandLineDuration {
    public static func parse(_ value: String) -> TimeInterval? {
        guard
            let match = value.wholeMatch(of: /([0-9]+(?:\.[0-9]+)?)([smh])/),
            let number = Double(match.1), number.isFinite, number > 0
        else {
            return nil
        }

        let multiplier: TimeInterval
        switch match.2 {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3600
        default: return nil
        }
        let duration = number * multiplier
        return duration.isFinite && duration > 0 ? duration : nil
    }
}
