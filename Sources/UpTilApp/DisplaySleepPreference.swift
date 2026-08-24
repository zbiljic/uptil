import Foundation

@MainActor
protocol DisplaySleepPreferenceManaging: AnyObject {
    var isEnabled: Bool { get set }
}

@MainActor
final class UserDefaultsDisplaySleepPreference: DisplaySleepPreferenceManaging {
    private static let key = "com.zbiljic.uptil.keepDisplayAwake"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get {
            defaults.bool(forKey: Self.key)
        }
        set {
            defaults.set(newValue, forKey: Self.key)
        }
    }
}
