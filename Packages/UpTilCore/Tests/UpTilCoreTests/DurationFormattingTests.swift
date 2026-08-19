import Testing
@testable import UpTilCore

@Suite("CompactDurationFormatter")
struct DurationFormattingTests {
    @Test("formats nonpositive and nonfinite values as zero minutes")
    func formatsEmptyDurations() {
        #expect(CompactDurationFormatter.string(remaining: 0) == "0m")
        #expect(CompactDurationFormatter.string(remaining: -1) == "0m")
        #expect(CompactDurationFormatter.string(remaining: .nan) == "0m")
        #expect(CompactDurationFormatter.string(remaining: .infinity) == "0m")
        #expect(CompactDurationFormatter.string(remaining: -.infinity) == "0m")
    }

    @Test("uses less than one minute below sixty seconds")
    func formatsPartialMinute() {
        #expect(CompactDurationFormatter.string(remaining: 1) == "<1m")
        #expect(CompactDurationFormatter.string(remaining: 59) == "<1m")
        #expect(CompactDurationFormatter.string(remaining: 59.999) == "<1m")
    }

    @Test("ceils minute values below an hour")
    func formatsMinuteBoundaries() {
        #expect(CompactDurationFormatter.string(remaining: 59 * 60) == "59m")
        #expect(CompactDurationFormatter.string(remaining: 59 * 60 + 1) == "60m")
    }

    @Test("formats an exact hour without a zero minute component")
    func formatsExactHour() {
        #expect(CompactDurationFormatter.string(remaining: 60 * 60) == "1h")
    }

    @Test("formats the first minute after an hour")
    func formatsMinuteAfterHour() {
        #expect(CompactDurationFormatter.string(remaining: 60 * 60 + 1) == "1h 1m")
        #expect(CompactDurationFormatter.string(remaining: 61 * 60) == "1h 1m")
    }

    @Test("formats multiple hours and minutes")
    func formatsHoursAndMinutes() {
        #expect(CompactDurationFormatter.string(remaining: 72 * 60) == "1h 12m")
        #expect(CompactDurationFormatter.string(remaining: 120 * 60) == "2h")
    }

    @Test("safely formats very large finite durations")
    func formatsLargeFiniteDuration() {
        let result = CompactDurationFormatter.string(remaining: Double.greatestFiniteMagnitude)

        #expect(result.contains("h"))
    }
}
