import Foundation
import Testing
@testable import UpTilCore

@Suite("Wall-clock deadline")
struct WallClockDeadlineTests {
    @Test("later time resolves today with seconds normalized")
    func laterToday() throws {
        let calendar = calendar(timeZoneIdentifier: "GMT")
        let now = try #require(date([2026, 8, 19, 10, 15, 42], calendar: calendar))
        let selection = try #require(date([2001, 1, 1, 18, 30, 59], calendar: calendar))
        let expected = try #require(date([2026, 8, 19, 18, 30, 0], calendar: calendar))

        #expect(WallClockDeadline.nextOccurrence(of: selection, after: now, calendar: calendar) == expected)
    }

    @Test("earlier time resolves tomorrow")
    func earlierTomorrow() throws {
        let calendar = calendar(timeZoneIdentifier: "GMT")
        let now = try #require(date([2026, 8, 19, 18, 30, 0], calendar: calendar))
        let selection = try #require(date([2001, 1, 1, 10, 15, 0], calendar: calendar))
        let expected = try #require(date([2026, 8, 20, 10, 15, 0], calendar: calendar))

        #expect(WallClockDeadline.nextOccurrence(of: selection, after: now, calendar: calendar) == expected)
    }

    @Test("current minute after its boundary resolves tomorrow")
    func currentMinuteTomorrow() throws {
        let calendar = calendar(timeZoneIdentifier: "GMT")
        let now = try #require(date([2026, 8, 19, 10, 15, 1], calendar: calendar))
        let selection = try #require(date([2001, 1, 1, 10, 15, 59], calendar: calendar))
        let expected = try #require(date([2026, 8, 20, 10, 15, 0], calendar: calendar))

        #expect(WallClockDeadline.nextOccurrence(of: selection, after: now, calendar: calendar) == expected)
    }

    @Test("rolls over a year boundary")
    func yearBoundary() throws {
        let calendar = calendar(timeZoneIdentifier: "GMT")
        let now = try #require(date([2026, 12, 31, 23, 0, 0], calendar: calendar))
        let selection = try #require(date([2001, 1, 1, 8, 30, 0], calendar: calendar))
        let expected = try #require(date([2027, 1, 1, 8, 30, 0], calendar: calendar))

        #expect(WallClockDeadline.nextOccurrence(of: selection, after: now, calendar: calendar) == expected)
    }

    @Test("spring-forward gap resolves to the next valid time")
    func springForwardGap() throws {
        let calendar = calendar(timeZoneIdentifier: "America/New_York")
        let now = try #require(date([2026, 3, 8, 0, 0, 0], calendar: calendar))
        let selection = try #require(date([2001, 1, 1, 2, 30, 0], calendar: calendar))
        let expected = try #require(date([2026, 3, 8, 3, 0, 0], calendar: calendar))

        #expect(WallClockDeadline.nextOccurrence(of: selection, after: now, calendar: calendar) == expected)
    }

    @Test("fall-back repeat resolves to the first occurrence")
    func fallBackRepeat() throws {
        let calendar = calendar(timeZoneIdentifier: "America/New_York")
        let now = try #require(date([2026, 11, 1, 0, 0, 0], calendar: calendar))
        let selection = try #require(date([2001, 1, 1, 1, 30, 0], calendar: calendar))
        let expected = try #require(date([2026, 11, 1, 1, 30, 0], calendar: calendar))

        #expect(WallClockDeadline.nextOccurrence(of: selection, after: now, calendar: calendar) == expected)
    }

    @Test("non-finite inputs return nil")
    func nonFiniteInputs() {
        let calendar = calendar(timeZoneIdentifier: "GMT")
        let valid = Date(timeIntervalSinceReferenceDate: 1000)
        let invalidDates = [
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity),
        ]

        for invalidDate in invalidDates {
            #expect(WallClockDeadline.nextOccurrence(of: invalidDate, after: valid, calendar: calendar) == nil)
            #expect(WallClockDeadline.nextOccurrence(of: valid, after: invalidDate, calendar: calendar) == nil)
        }
    }

    private func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return calendar
    }

    private func date(_ values: [Int], calendar: Calendar) -> Date? {
        guard values.count == 6 else {
            return nil
        }

        return calendar.date(from: DateComponents(
            year: values[0],
            month: values[1],
            day: values[2],
            hour: values[3],
            minute: values[4],
            second: values[5]
        ))
    }
}
