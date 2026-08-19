import Foundation
import Testing
@testable import UpTil

@MainActor
@Suite("ProcessInfo keep-awake service")
struct KeepAwakeServiceTests {
    @Test("activation and deactivation are idempotent")
    func activityLifecycleIsIdempotent() {
        var beginCount = 0
        var endCount = 0
        var receivedOptions: [ProcessInfo.ActivityOptions] = []
        var receivedReasons: [String] = []
        let service = ProcessInfoKeepAwakeService(
            beginActivity: { options, reason in
                beginCount += 1
                receivedOptions.append(options)
                receivedReasons.append(reason)
                return NSObject()
            },
            endActivity: { _ in
                endCount += 1
            }
        )

        service.activate()
        service.activate()

        #expect(service.isActive)
        #expect(beginCount == 1)
        #expect(receivedOptions == [[.idleSystemSleepDisabled]])
        #expect(receivedReasons == ["UpTil keep-awake session"])

        service.deactivate()
        service.deactivate()

        #expect(!service.isActive)
        #expect(endCount == 1)
    }
}
