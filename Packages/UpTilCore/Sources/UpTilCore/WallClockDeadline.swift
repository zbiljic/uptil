import Foundation

public enum WallClockDeadline {
    public static func nextOccurrence(
        of selectedTime: Date,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        guard
            selectedTime.timeIntervalSinceReferenceDate.isFinite,
            now.timeIntervalSinceReferenceDate.isFinite
        else {
            return nil
        }

        let selectedComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
        guard let hour = selectedComponents.hour, let minute = selectedComponents.minute else {
            return nil
        }

        var matchingComponents = DateComponents()
        matchingComponents.hour = hour
        matchingComponents.minute = minute
        matchingComponents.second = 0

        guard
            let deadline = calendar.nextDate(
                after: now,
                matching: matchingComponents,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ), deadline.timeIntervalSinceReferenceDate.isFinite, deadline > now
        else {
            return nil
        }

        return deadline
    }
}
