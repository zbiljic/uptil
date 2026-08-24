import Darwin
import Foundation
import UpTilCore

@MainActor
final class MCPControlServer {
    struct SocketIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let owner: uid_t
    }

    private let handler: MCPCommandHandler
    private var listener: Int32 = -1
    private var socketURL: URL?
    private var socketIdentity: SocketIdentity?

    init(handler: MCPCommandHandler) {
        self.handler = handler
    }

    func start(at requestedURL: URL? = nil) {
        guard
            listener < 0,
            let path = requestedURL ?? Self.socketURL(),
            Self.prepareParent(for: path),
            Self.removeOnlyStaleSocket(at: path)
        else { return }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }
        guard Self.configureSocket(descriptor) else {
            close(descriptor)
            return
        }
        guard Self.bindSocket(descriptor, path: path.path) == 0 else {
            close(descriptor)
            return
        }
        guard let boundIdentity = Self.socketIdentity(at: path) else {
            close(descriptor)
            return
        }
        guard
            chmod(path.path, 0o600) == 0,
            Darwin.listen(descriptor, 16) == 0,
            let identity = Self.identity(at: path), identity == boundIdentity
        else {
            close(descriptor)
            Self.unlinkIfMatching(path: path.path, identity: boundIdentity)
            return
        }
        listener = descriptor
        socketURL = path
        socketIdentity = identity
        let handler = handler
        Task.detached {
            await Self.acceptLoop(listener: descriptor, handler: handler)
        }
    }

    func stop() {
        let descriptor = listener
        listener = -1
        if descriptor >= 0 {
            close(descriptor)
        }
        if let path = socketURL, let identity = socketIdentity {
            Self.unlinkIfMatching(path: path.path, identity: identity)
        }
        socketURL = nil
        socketIdentity = nil
    }

    private static func socketURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let suffix = "/Library/Containers/\(UpTilCore.appBundleIdentifier)/Data"
        return ControlSocketPath.socketURL(home: home, runningInsideContainer: home.path.hasSuffix(suffix))
    }

    static func prepareParent(for socket: URL) -> Bool {
        let directory = socket.deletingLastPathComponent()
        var status = stat()
        if lstat(directory.path, &status) != 0 {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                return false
            }
            guard lstat(directory.path, &status) == 0 else { return false }
        }
        return isSafeParentMetadata(mode: status.st_mode, owner: status.st_uid)
    }

    static func removeOnlyStaleSocket(at path: URL) -> Bool {
        var status = stat()
        guard lstat(path.path, &status) == 0 else { return errno == ENOENT }
        guard isPrivateSocketMetadata(mode: status.st_mode, owner: status.st_uid) else {
            return false
        }
        let identity = SocketIdentity(device: status.st_dev, inode: status.st_ino, owner: status.st_uid)
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        guard Self.setTimeouts(probe) else { return false }
        if Self.connectSocket(probe, path: path.path) == 0 {
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(probe, &uid, &gid) == 0, uid == getuid() else { return false }
            return false
        }
        guard errno == ECONNREFUSED || errno == ENOENT else { return false }
        guard socketIdentity(at: path) == identity else { return false }
        return unlink(path.path) == 0
    }

    nonisolated static func identity(at path: URL) -> SocketIdentity? {
        var status = stat()
        guard
            lstat(path.path, &status) == 0,
            isPublishedSocketMetadata(mode: status.st_mode, owner: status.st_uid)
        else { return nil }
        return SocketIdentity(device: status.st_dev, inode: status.st_ino, owner: status.st_uid)
    }

    nonisolated static func socketIdentity(at path: URL) -> SocketIdentity? {
        var status = stat()
        guard
            lstat(path.path, &status) == 0,
            isRawSocketMetadata(mode: status.st_mode, owner: status.st_uid)
        else { return nil }
        return SocketIdentity(device: status.st_dev, inode: status.st_ino, owner: status.st_uid)
    }

    nonisolated static func unlinkIfMatching(path: String, identity: SocketIdentity) {
        guard socketIdentity(at: URL(fileURLWithPath: path)) == identity else { return }
        _ = unlink(path)
    }

    nonisolated private static func acceptLoop(listener: Int32, handler: MCPCommandHandler) async {
        while true {
            let connection = accept(listener, nil, nil)
            if connection < 0 {
                if errno == EINTR {
                    continue
                }
                return
            }
            guard Self.configureSocket(connection) else {
                close(connection)
                continue
            }
            await Self.handle(connection, handler: handler)
        }
    }

    nonisolated private static func handle(_ descriptor: Int32, handler: MCPCommandHandler) async {
        defer { close(descriptor) }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard
            getpeereid(descriptor, &uid, &gid) == 0, uid == getuid(),
            let request = readLine(descriptor) else { return }
        guard let response = await handler.response(for: request), let line = try? MCPFraming.line(for: response) else {
            return
        }
        _ = writeAll(descriptor, line)
    }

    nonisolated static func bindSocket(_ descriptor: Int32, path: String) -> Int32 {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    nonisolated private static func connectSocket(_ descriptor: Int32, path: String) -> Int32 {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    nonisolated private static func readLine(_ descriptor: Int32) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while data.count <= MCPFraming.maximumLineBytes {
            let count = read(descriptor, &byte, 1)
            if count < 0, errno == EINTR {
                continue
            }
            guard count == 1 else { return nil }
            data.append(byte)
            if byte == 0x0A {
                return try? MCPFraming.objectData(from: data)
            }
        }
        return nil
    }

    nonisolated private static func writeAll(_ descriptor: Int32, _ data: Data) -> Bool {
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return -1 }
                return write(descriptor, base.advanced(by: offset), data.count - offset)
            }
            if count < 0, errno == EINTR {
                continue
            }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }

    nonisolated static func configureSocket(_ descriptor: Int32) -> Bool {
        var noSigPipe: Int32 = 1
        guard
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            ) == 0
        else { return false }
        return setTimeouts(descriptor)
    }

    nonisolated static func setTimeouts(_ descriptor: Int32) -> Bool {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        guard
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            ) == 0 else { return false }
        return setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0
    }

    nonisolated static func isSafeParentMetadata(
        mode: mode_t,
        owner: uid_t,
        currentUID: uid_t = getuid()
    ) -> Bool {
        (mode & S_IFMT) == S_IFDIR && owner == currentUID && mode & 0o077 == 0
    }

    nonisolated static func isRawSocketMetadata(
        mode: mode_t,
        owner: uid_t,
        currentUID: uid_t = getuid()
    ) -> Bool {
        (mode & S_IFMT) == S_IFSOCK && owner == currentUID
    }

    nonisolated static func isPrivateSocketMetadata(
        mode: mode_t,
        owner: uid_t,
        currentUID: uid_t = getuid()
    ) -> Bool {
        isRawSocketMetadata(mode: mode, owner: owner, currentUID: currentUID) && mode & 0o077 == 0
    }

    nonisolated static func isPublishedSocketMetadata(
        mode: mode_t,
        owner: uid_t,
        currentUID: uid_t = getuid()
    ) -> Bool {
        isRawSocketMetadata(mode: mode, owner: owner, currentUID: currentUID) && mode & 0o777 == 0o600
    }
}
