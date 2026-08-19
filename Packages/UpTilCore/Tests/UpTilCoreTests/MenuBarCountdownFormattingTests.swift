import Foundation
import Testing
@testable import UpTilCore

@Suite("Menu bar countdown formatting")
struct MenuBarCountdownFormattingTests {
    @Test("defensive values always show one minute")
    func defensiveValuesShowOneMinute() {
        #expect(MenuBarCountdownFormatting.string(remaining: 0) == "⟩1m⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: -1) == "⟩1m⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: .infinity) == "⟩1m⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: .nan) == "⟩1m⟨")
        #expect(MenuBarCountdownFormatting.durationString(remaining: 0) == "1m")
    }

    @Test("sub-minute values round up and exact minute values stay positive")
    func subMinuteAndExactMinuteBoundaries() {
        #expect(MenuBarCountdownFormatting.string(remaining: 0.001) == "⟩1m⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 59.999) == "⟩1m⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 60) == "⟩1m⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 60 * 60 - 0.001) == "⟩60m⟨")
    }

    @Test("the 60 minute threshold uses compact hours and minutes")
    func sixtyMinuteThreshold() {
        #expect(MenuBarCountdownFormatting.string(remaining: 60 * 60) == "⟩1h⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 60 * 60 + 1) == "⟩1h1m⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 79 * 60 + 1) == "⟩1h20m⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 90 * 60 - 0.001) == "⟩1h30m⟨")
    }

    @Test("the 90 minute threshold rounds to whole hours")
    func ninetyMinuteThreshold() {
        #expect(MenuBarCountdownFormatting.string(remaining: 90 * 60) == "⟩2h⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 90 * 60 + 1) == "⟩2h⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 120 * 60) == "⟩2h⟨")
        #expect(MenuBarCountdownFormatting.string(remaining: 120 * 60 + 1) == "⟩3h⟨")
    }

    @Test("refresh delays are positive at every display boundary")
    func refreshDelaysArePositive() {
        let values = [
            0.0,
            60.0,
            60 * 60.0,
            90 * 60.0,
            120 * 60.0,
        ]

        for value in values {
            #expect(MenuBarCountdownFormatting.nextRefreshDelay(remaining: value) > 0)
        }

        #expect(MenuBarCountdownFormatting.nextRefreshDelay(remaining: 79 * 60 + 1) > 1)
        #expect(MenuBarCountdownFormatting.nextRefreshDelay(remaining: 2 * 60 * 60 + 1) > 1)
        #expect(MenuBarCountdownFormatting.nextRefreshDelay(remaining: 60 * 60) < 1)
        #expect(MenuBarCountdownFormatting.nextRefreshDelay(remaining: 60 * 60 + 1) < 2)
        #expect(
            MenuBarCountdownFormatting.nextRefreshDelay(remaining: .greatestFiniteMagnitude)
                == 60 * 60
        )
    }

    @Test("refresh scheduling crosses every display bucket in the first day")
    func refreshSchedulingCrossesDisplayBuckets() {
        for remaining in stride(from: 60.125, through: 24 * 60 * 60.0, by: 17.0) {
            let before = MenuBarCountdownFormatting.string(remaining: remaining)
            let delay = MenuBarCountdownFormatting.nextRefreshDelay(remaining: remaining)
            let after = MenuBarCountdownFormatting.string(remaining: remaining - delay)

            #expect(delay.isFinite)
            #expect(delay > 0)
            #expect(after != before)
        }
    }

    @Test("hour boundary delays cross the boundary without stale displays")
    func hourBoundaryDelaysCrossTheBoundary() {
        let justAboveTwoHours = 2 * 60 * 60.0 + 0.001
        let justAboveTwoHoursDelay = MenuBarCountdownFormatting.nextRefreshDelay(
            remaining: justAboveTwoHours
        )
        #expect(justAboveTwoHoursDelay > 0.001)
        #expect(justAboveTwoHoursDelay < 0.1)
        #expect(
            MenuBarCountdownFormatting.string(remaining: justAboveTwoHours - justAboveTwoHoursDelay)
                == "⟩2h⟨"
        )

        let exactTwoHours = 2 * 60 * 60.0
        let exactTwoHoursDelay = MenuBarCountdownFormatting.nextRefreshDelay(remaining: exactTwoHours)
        #expect(exactTwoHoursDelay > 1800)
        #expect(exactTwoHoursDelay < 1801)
        #expect(
            MenuBarCountdownFormatting.string(remaining: exactTwoHours - exactTwoHoursDelay)
                == "⟩1h30m⟨"
        )

        let exactThreeHours = 3 * 60 * 60.0
        let exactThreeHoursDelay = MenuBarCountdownFormatting.nextRefreshDelay(remaining: exactThreeHours)
        #expect(exactThreeHoursDelay > 3600)
        #expect(exactThreeHoursDelay < 3601)
        #expect(
            MenuBarCountdownFormatting.string(remaining: exactThreeHours - exactThreeHoursDelay)
                == "⟩2h⟨"
        )
    }

    @Test("minute boundary delays cross positive remainders")
    func minuteBoundaryDelaysCrossPositiveRemainders() {
        let justAboveFortyTwoMinutes = 42 * 60.0 + 0.001
        let justAboveFortyTwoMinutesDelay = MenuBarCountdownFormatting.nextRefreshDelay(
            remaining: justAboveFortyTwoMinutes
        )
        #expect(justAboveFortyTwoMinutesDelay > 0.001)
        #expect(justAboveFortyTwoMinutesDelay < 0.1)
        #expect(
            MenuBarCountdownFormatting.string(remaining: justAboveFortyTwoMinutes)
                == "⟩43m⟨"
        )
        #expect(
            MenuBarCountdownFormatting.string(remaining: justAboveFortyTwoMinutes - justAboveFortyTwoMinutesDelay)
                == "⟩42m⟨"
        )

        let justAboveSeventyNineMinutes = 79 * 60.0 + 0.001
        let justAboveSeventyNineMinutesDelay = MenuBarCountdownFormatting.nextRefreshDelay(
            remaining: justAboveSeventyNineMinutes
        )
        #expect(justAboveSeventyNineMinutesDelay > 0.001)
        #expect(justAboveSeventyNineMinutesDelay < 0.1)
        #expect(
            MenuBarCountdownFormatting.string(remaining: justAboveSeventyNineMinutes - justAboveSeventyNineMinutesDelay)
                == "⟩1h19m⟨"
        )

        let exactFortyTwoMinutes = 42 * 60.0
        let exactFortyTwoMinutesDelay = MenuBarCountdownFormatting.nextRefreshDelay(remaining: exactFortyTwoMinutes)
        #expect(exactFortyTwoMinutesDelay > 60)
        #expect(exactFortyTwoMinutesDelay < 61)
    }
}
