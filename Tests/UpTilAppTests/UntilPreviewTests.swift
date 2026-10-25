import Foundation
import Testing
@testable import UpTil

@Suite("Until preview")
struct UntilPreviewTests {
    @Test("preview shows the session length next to the end time")
    func previewShowsLength() {
        let now = Date(timeIntervalSince1970: 0)
        let preview = UntilDeadlineFormatting.string(
            for: now.addingTimeInterval(50 * 60),
            now: now,
            locale: Locale(identifier: "en_GB"),
            timeZone: .gmt
        )

        #expect(preview == "Ends today at 00:50 · 50m")
    }

    @Test("sessions from twelve hours on stand out")
    func longSessionBoundary() {
        let now = Date(timeIntervalSince1970: 0)

        #expect(!UntilDeadlineFormatting.isLongSession(ending: now.addingTimeInterval(12 * 3600 - 1), now: now))
        #expect(UntilDeadlineFormatting.isLongSession(ending: now.addingTimeInterval(12 * 3600), now: now))
    }
}
