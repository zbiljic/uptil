import Foundation
import SwiftUI
import Testing
@testable import UpTil

@MainActor
@Suite("Countdown hero")
struct CountdownHeroTests {
    @Test("a zero hour is faded instead of dropped")
    func zeroHourIsFaded() {
        #expect(CountdownFormatting.parts(remaining: 2700) == .init(fadedPrefix: "0:", value: "45:00"))
        #expect(CountdownFormatting.parts(remaining: 45) == .init(fadedPrefix: "0:", value: "00:45"))
        #expect(CountdownFormatting.parts(remaining: 5400) == .init(fadedPrefix: "", value: "1:30:00"))
        #expect(CountdownFormatting.parts(remaining: 36900) == .init(fadedPrefix: "", value: "10:15:00"))
    }

    @Test("remaining time rounds up and clamps at zero")
    func remainingRoundsUpAndClamps() {
        #expect(CountdownFormatting.parts(remaining: 2699.2).value == "45:00")
        #expect(CountdownFormatting.parts(remaining: 0.2).value == "00:01")
        for remaining in [0, -5, TimeInterval.nan, -TimeInterval.infinity] {
            #expect(CountdownFormatting.parts(remaining: remaining) == .init(fadedPrefix: "0:", value: "00:00"))
        }
    }

    @Test("the countdown keeps one width below ten hours", arguments: [1.0, 59, 900, 3599, 3600, 5400, 35999])
    func widthIsStableBelowTenHours(remaining: TimeInterval) {
        let parts = CountdownFormatting.parts(remaining: remaining)
        #expect((parts.fadedPrefix + parts.value).count == "0:00:00".count)
    }

    @Test("accessibility reads the duration in words")
    func accessibilityReadsWords() {
        let english = Locale(identifier: "en_US")
        #expect(CountdownFormatting.accessibilityDuration(remaining: 2700, locale: english) == "45 minutes")
        #expect(CountdownFormatting.accessibilityDuration(remaining: 5400, locale: english) == "1 hour, 30 minutes")
        #expect(CountdownFormatting.accessibilityDuration(remaining: 44.5, locale: english) == "45 seconds")
    }

    @Test("ticks align with the deadline's second boundaries and stop at the deadline")
    func scheduleAlignsWithDeadline() throws {
        let deadline = Date(timeIntervalSinceReferenceDate: 10000.25)
        let start = deadline.addingTimeInterval(-3.6)
        let schedule = CountdownTimelineSchedule(deadline: deadline)

        let entries = Array(schedule.entries(from: start, mode: .normal))

        #expect(entries == [-4.0, -3, -2, -1, 0].map { deadline.addingTimeInterval($0) })
        #expect(try #require(entries.first) <= start)
        #expect(Array(schedule.entries(from: deadline.addingTimeInterval(5), mode: .normal)) == [deadline])
    }
}
