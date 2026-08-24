import Foundation

@MainActor
protocol KeepAwakeManaging: AnyObject {
    var isActive: Bool { get }
    var isDisplaySleepPreventionActive: Bool { get }

    func activate()
    func setDisplaySleepPreventionEnabled(_ enabled: Bool)
    func deactivate()
}

@MainActor
final class ProcessInfoKeepAwakeService: KeepAwakeManaging {
    typealias BeginActivity = @MainActor (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol
    typealias EndActivity = @MainActor (NSObjectProtocol) -> Void

    private let beginActivity: BeginActivity
    private let endActivity: EndActivity
    private var systemActivityToken: NSObjectProtocol?
    private var displayActivityToken: NSObjectProtocol?

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
        systemActivityToken != nil
    }

    var isDisplaySleepPreventionActive: Bool {
        displayActivityToken != nil
    }

    func activate() {
        guard systemActivityToken == nil else {
            return
        }

        systemActivityToken = beginActivity(
            [.idleSystemSleepDisabled],
            "UpTil keep-awake session"
        )
    }

    func setDisplaySleepPreventionEnabled(_ enabled: Bool) {
        if enabled {
            guard systemActivityToken != nil, displayActivityToken == nil else {
                return
            }

            displayActivityToken = beginActivity(
                [.idleDisplaySleepDisabled],
                "UpTil display-awake option"
            )
            return
        }

        guard let displayActivityToken else {
            return
        }

        self.displayActivityToken = nil
        endActivity(displayActivityToken)
    }

    func deactivate() {
        if let displayActivityToken {
            self.displayActivityToken = nil
            endActivity(displayActivityToken)
        }

        if let systemActivityToken {
            self.systemActivityToken = nil
            endActivity(systemActivityToken)
        }
    }

    deinit {
        // Swift 6 deinitializers cannot safely access this main-actor token.
        // SessionController performs explicit, idempotent cleanup via shutdown().
    }
}
