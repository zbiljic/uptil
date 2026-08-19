import Foundation

@MainActor
protocol KeepAwakeManaging: AnyObject {
    var isActive: Bool { get }

    func activate()
    func deactivate()
}

@MainActor
final class ProcessInfoKeepAwakeService: KeepAwakeManaging {
    typealias BeginActivity = @MainActor (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol
    typealias EndActivity = @MainActor (NSObjectProtocol) -> Void

    private let beginActivity: BeginActivity
    private let endActivity: EndActivity
    private var activityToken: NSObjectProtocol?

    init(
        beginActivity: @escaping BeginActivity = { options, reason in
            ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
        },
        endActivity: @escaping EndActivity = { token in
            ProcessInfo.processInfo.endActivity(token)
        }
    ) {
        self.beginActivity = beginActivity
        self.endActivity = endActivity
    }

    var isActive: Bool {
        activityToken != nil
    }

    func activate() {
        guard activityToken == nil else {
            return
        }

        activityToken = beginActivity(
            [.idleSystemSleepDisabled],
            "UpTil keep-awake session"
        )
    }

    func deactivate() {
        guard let activityToken else {
            return
        }

        self.activityToken = nil
        endActivity(activityToken)
    }

    deinit {
        // Swift 6 deinitializers cannot safely access this main-actor token.
        // SessionController performs explicit, idempotent cleanup via shutdown().
    }
}
