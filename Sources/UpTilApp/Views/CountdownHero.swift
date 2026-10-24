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
            let endTime = EndTimeFormatting.string(for: deadline, now: context.date)

            CountdownHeroContent(remaining: remaining, caption: "remaining · ends \(endTime)")
                .accessibilityLabel(
                    "\(CountdownFormatting.accessibilityDuration(remaining: remaining)) remaining, session ends \(endTime)"
                )
        }
    }
}

enum PausedSessionPresentation {
    static let caption = "Paused — Mac may sleep"

    static func accessibilityLabel(remaining: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        let duration = CountdownFormatting.accessibilityDuration(remaining: remaining, locale: locale)
        return "Paused with \(duration) remaining. The Mac may sleep."
    }
}

/// The frozen countdown of a paused session. It shows no end time, because resuming moves the end later.
struct PausedCountdownHero: View {
    let remaining: TimeInterval

    var body: some View {
        CountdownHeroContent(remaining: remaining, caption: PausedSessionPresentation.caption)
            .accessibilityLabel(PausedSessionPresentation.accessibilityLabel(remaining: remaining))
    }
}

private struct CountdownHeroContent: View {
    let remaining: TimeInterval
    let caption: String

    var body: some View {
        let parts = CountdownFormatting.parts(remaining: remaining)

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

            Text(caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
    }
}
