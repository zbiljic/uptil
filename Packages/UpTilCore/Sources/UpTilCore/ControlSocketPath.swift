import Foundation

public enum ControlSocketPath {
    public static let socketName = "uptil.sock"
    public static let maximumPathBytes = 103

    public static func applicationContainer(
        home: URL,
        bundleIdentifier: String = UpTilCore.appBundleIdentifier
    ) -> URL {
        home.appending(path: "Library/Containers").appending(path: bundleIdentifier).appending(path: "Data")
    }

    public static func socketURL(
        home: URL,
        runningInsideContainer: Bool,
        bundleIdentifier: String = UpTilCore.appBundleIdentifier
    ) -> URL? {
        let dataDirectory = runningInsideContainer ? home : applicationContainer(
            home: home,
            bundleIdentifier: bundleIdentifier
        )
        let socket = dataDirectory.appending(path: "tmp").appending(path: socketName)
        return socket.path.utf8.count + 1 <= maximumPathBytes ? socket : nil
    }
}
