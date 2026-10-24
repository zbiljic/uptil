import SwiftUI

/// Ticks on the deadline's own second boundaries, so the rounded-up countdown changes
/// exactly when a whole second elapses rather than up to a second late.
struct CountdownTimelineSchedule: TimelineSchedule {
    let deadline: Date

    func entries(from startDate: Date, mode _: TimelineScheduleMode) -> some Sequence<Date> {
        let remaining = max(0, deadline.timeIntervalSince(startDate))
        let first = deadline.addingTimeInterval(-remaining.rounded(.up))
        return sequence(first: first) { date in
            date < deadline ? date.addingTimeInterval(1) : nil
        }
    }
}

struct CountdownHero: View {
    let deadline: Date

    var body: some View {
        TimelineView(CountdownTimelineSchedule(deadline: deadline)) { context in
            let remaining = deadline.timeIntervalSince(context.date)
            let parts = CountdownFormatting.parts(remaining: remaining)
            let endTime = EndTimeFormatting.string(for: deadline, now: context.date)

            VStack(spacing: 0) {
                // The hidden template fixes the width below ten hours. Trailing alignment keeps
                // minutes and seconds in place when a tenth hour digit overflows to the left.
                Text(verbatim: "0:00:00")
                    .hidden()
                    .overlay(alignment: .trailing) {
                        (Text(parts.fadedPrefix).foregroundStyle(.tertiary) + Text(parts.value))
                            .fixedSize()
                    }
                    .font(SessionPopoverLayout.heroFont)

                Text("remaining · ends \(endTime)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(CountdownFormatting.accessibilityDuration(remaining: remaining)) remaining, session ends \(endTime)"
            )
        }
    }
}
