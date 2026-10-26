import Foundation
import UpTilCore

enum AppMetadata {
    static let bundleIdentifier = UpTilCore.appBundleIdentifier

    /// Where the About menu sends people: the public project page and its issue tracker.
    static let projectPageURL = URL(string: "https://github.com/zbiljic/uptil")
    static let issuesURL = URL(string: "https://github.com/zbiljic/uptil/issues")

    /// The marketing version baked into the bundle, or `nil` when running outside a built app.
    static func version(from bundle: Bundle = .main) -> String? {
        guard
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !version.isEmpty
        else {
            return nil
        }

        return version
    }
}
