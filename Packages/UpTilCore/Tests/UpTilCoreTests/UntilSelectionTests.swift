import Foundation
import Testing
@testable import UpTilCore

@Suite("Until selection")
struct UntilSelectionTests {
    private let calendar = makeCalendar(timeZoneIdentifier: "GMT")

    @Test("suggestion is 45 minutes ahead, rounded up to the quarter hour")
    func suggestionRoundsUp() throws {
        let selection = UntilSelection()
        let cases: [(now: [Int], expected: [Int])] = [
            ([10, 20, 0], [11, 15]),
            ([10, 30, 0], [11, 15]),
            ([10, 30, 1], [11, 30]),
            ([23, 50, 0], [0, 45]),
        ]

        for testCase in cases {
            let now = try date(hour: testCase.now[0], minute: testCase.now[1], second: testCase.now[2])
            let deadline = try #require(selection.deadline(at: now, calendar: calendar))
            #expect(components(of: deadline) == testCase.expected)
            #expect(deadline.timeIntervalSince(now) >= 45 * 60)
            #expect(deadline.timeIntervalSince(now) < 60 * 60)
        }
    }

    @Test("an untouched suggestion follows the clock")
    func suggestionFollowsClock() throws {
        let selection = UntilSelection()

        #expect(try selection.deadline(at: date(hour: 10, minute: 20), calendar: calendar) == date(
            hour: 11,
            minute: 15
        ))
        #expect(try selection.deadline(at: date(hour: 10, minute: 31), calendar: calendar) == date(
            hour: 11,
            minute: 30
        ))
    }

    @Test("a picked time holds until it passes")
    func pickHoldsUntilItPasses() throws {
        var selection = UntilSelection()
        try selection.pick(date(hour: 18, minute: 0), at: date(hour: 10, minute: 20), calendar: calendar)

        let pick = try date(hour: 18, minute: 0)
        #expect(selection.deadline(at: pick.addingTimeInterval(-1), calendar: calendar) == pick)
        #expect(try selection.deadline(at: pick, calendar: calendar) == date(hour: 18, minute: 45))
    }

    @Test("an earlier clock time holds until tomorrow")
    func earlierPickHoldsUntilTomorrow() throws {
        var selection = UntilSelection()
        try selection.pick(date(hour: 8, minute: 0), at: date(hour: 9, minute: 40), calendar: calendar)

        let tomorrow = try date(day: 20, hour: 8, minute: 0)
        #expect(try selection.deadline(at: date(hour: 9, minute: 41), calendar: calendar) == tomorrow)
        #expect(try selection.deadline(at: date(hour: 23, minute: 0), calendar: calendar) == tomorrow)
    }

    @Test("committing the shown time keeps the suggestion moving")
    func committingShownTimeKeepsFollowing() throws {
        var selection = UntilSelection()
        let now = try date(hour: 10, minute: 20)
        let shownOnAnotherDay = try #require(calendar.date(from: DateComponents(
            year: 2001,
            month: 1,
            day: 1,
            hour: 11,
            minute: 15
        )))

        selection.pick(shownOnAnotherDay, at: now, calendar: calendar)

        #expect(try selection.deadline(at: date(hour: 10, minute: 31), calendar: calendar) == date(
            hour: 11,
            minute: 30
        ))
    }

    @Test("a pick is forgotten after the popover stays closed for ten minutes")
    func closedPopoverForgetsPick() throws {
        let pick = try date(hour: 18, minute: 0)
        var selection = UntilSelection()
        try selection.pick(pick, at: date(hour: 10, minute: 20), calendar: calendar)

        var briefly = selection
        try briefly.popoverDidClose(at: date(hour: 10, minute: 21))
        try briefly.popoverDidOpen(at: date(hour: 10, minute: 30, second: 59))
        #expect(try briefly.deadline(at: date(hour: 10, minute: 31), calendar: calendar) == pick)

        var long = selection
        try long.popoverDidClose(at: date(hour: 10, minute: 21))
        try long.popoverDidClose(at: date(hour: 10, minute: 29))
        try long.popoverDidOpen(at: date(hour: 10, minute: 31))
        #expect(try long.deadline(at: date(hour: 10, minute: 31), calendar: calendar) == date(hour: 11, minute: 30))
    }

    @Test("the suggestion stays 45 to 59 minutes away across clock changes")
    func suggestionAcrossClockChanges() throws {
        let transitions: [(zone: String, around: String)] = [
            ("Europe/Belgrade", "2026-10-25T01:00:00Z"),
            ("America/New_York", "2026-03-08T07:00:00Z"),
        ]
        let selection = UntilSelection()

        for transition in transitions {
            let zoneCalendar = makeCalendar(timeZoneIdentifier: transition.zone)
            let center = try #require(ISO8601DateFormatter().date(from: transition.around))

            for step in stride(from: -3 * 3600.0, through: 3 * 3600.0, by: 433) {
                let now = center.addingTimeInterval(step)
                let deadline = try #require(selection.deadline(at: now, calendar: zoneCalendar))
                let lead = deadline.timeIntervalSince(now)
                #expect(lead >= 45 * 60, "\(transition.zone) at \(now)")
                #expect(lead < 60 * 60, "\(transition.zone) at \(now)")
                #expect(zoneCalendar.component(.minute, from: deadline).isMultiple(of: 15))
                #expect(zoneCalendar.component(.second, from: deadline) == 0)
            }
        }
    }

    @Test("a non-finite time yields no deadline")
    func nonFiniteTime() {
        #expect(UntilSelection().deadline(at: Date(timeIntervalSinceReferenceDate: .nan), calendar: calendar) == nil)
    }

    private func date(day: Int = 19, hour: Int, minute: Int, second: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )))
    }

    private func components(of date: Date) -> [Int] {
        [calendar.component(.hour, from: date), calendar.component(.minute, from: date)]
    }
}

private func makeCalendar(timeZoneIdentifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    return calendar
}
