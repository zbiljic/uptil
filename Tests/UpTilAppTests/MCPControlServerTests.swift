import Darwin
import Foundation
import Testing
@testable import UpTil
import UpTilCore

@MainActor
@Suite("MCP control server")
struct MCPControlServerTests {
    @Test("parent creation and path bounds fail closed")
    func parentAndPathSafety() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appending(path: "control/uptil.sock")

        #expect(MCPControlServer.prepareParent(for: socket))
        var status = stat()
        #expect(lstat(socket.deletingLastPathComponent().path, &status) == 0)
        #expect(status.st_mode & 0o777 == 0o700)
        #expect(status.st_uid == getuid())

        #expect(chmod(socket.deletingLastPathComponent().path, 0o755) == 0)
        #expect(!MCPControlServer.prepareParent(for: socket))

        let descriptor = try #require(makeSocket())
        defer { close(descriptor) }
        #expect(MCPControlServer.bindSocket(descriptor, path: String(repeating: "x", count: 512)) == -1)
    }

    @Test("parent symlinks and foreign metadata are rejected")
    func parentLinkAndForeignOwner() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realParent = root.appending(path: "real")
        let linkedParent = root.appending(path: "linked")
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: realParent)
        #expect(!MCPControlServer.prepareParent(for: linkedParent.appending(path: "uptil.sock")))

        let socketMode = mode_t(S_IFSOCK) | 0o600
        #expect(!MCPControlServer.isRawSocketMetadata(
            mode: socketMode,
            owner: 501,
            currentUID: 502
        ))
        #expect(!MCPControlServer.isSafeParentMetadata(
            mode: mode_t(S_IFDIR) | 0o700,
            owner: 501,
            currentUID: 502
        ))

        #expect(MCPControlServer.isRawSocketMetadata(mode: socketMode, owner: 501, currentUID: 501))
        #expect(MCPControlServer.isPrivateSocketMetadata(mode: socketMode, owner: 501, currentUID: 501))
        #expect(MCPControlServer.isPublishedSocketMetadata(mode: socketMode, owner: 501, currentUID: 501))
        #expect(!MCPControlServer.isPrivateSocketMetadata(
            mode: mode_t(S_IFSOCK) | 0o666,
            owner: 501,
            currentUID: 501
        ))
        #expect(!MCPControlServer.isPublishedSocketMetadata(
            mode: mode_t(S_IFSOCK) | 0o700,
            owner: 501,
            currentUID: 501
        ))
    }

    @Test("only safe stale socket nodes are removed")
    func staleSocketCleanup() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appending(path: "stale.sock")
        try bindSocketNode(at: path, permissions: 0o600)
        #expect(MCPControlServer.removeOnlyStaleSocket(at: path))
        #expect(!FileManager.default.fileExists(atPath: path.path))

        let active = root.appending(path: "active.sock")
        let descriptor = try #require(makeSocket())
        defer { close(descriptor) }
        #expect(MCPControlServer.bindSocket(descriptor, path: active.path) == 0)
        #expect(chmod(active.path, 0o600) == 0)
        #expect(Darwin.listen(descriptor, 1) == 0)
        #expect(!MCPControlServer.removeOnlyStaleSocket(at: active))
        #expect(FileManager.default.fileExists(atPath: active.path))
    }

    @Test("links files and unsafe socket modes are never removed")
    func unsafeNodes() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let regular = root.appending(path: "regular")
        try Data("keep".utf8).write(to: regular)
        #expect(!MCPControlServer.removeOnlyStaleSocket(at: regular))
        #expect(FileManager.default.fileExists(atPath: regular.path))

        let target = root.appending(path: "target")
        let link = root.appending(path: "link")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(!MCPControlServer.removeOnlyStaleSocket(at: link))
        var linkStatus = stat()
        #expect(lstat(link.path, &linkStatus) == 0)
        #expect(linkStatus.st_mode & S_IFMT == S_IFLNK)

        let unsafeSocket = root.appending(path: "unsafe.sock")
        try bindSocketNode(at: unsafeSocket, permissions: 0o666)
        #expect(!MCPControlServer.removeOnlyStaleSocket(at: unsafeSocket))
        #expect(FileManager.default.fileExists(atPath: unsafeSocket.path))
    }

    @Test("server installs timeouts and owns a mode 0600 socket")
    func socketConfiguration() throws {
        let descriptor = try #require(makeSocket())
        defer { close(descriptor) }
        #expect(MCPControlServer.configureSocket(descriptor))
        #expect(!MCPControlServer.configureSocket(-1))

        var receiveTimeout = timeval()
        var receiveLength = socklen_t(MemoryLayout<timeval>.size)
        #expect(getsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, &receiveLength) == 0)
        #expect(receiveTimeout.tv_sec == 5)
        var sendTimeout = timeval()
        var sendLength = socklen_t(MemoryLayout<timeval>.size)
        #expect(getsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, &sendLength) == 0)
        #expect(sendTimeout.tv_sec == 5)
        var noSigPipe: Int32 = 0
        var flagLength = socklen_t(MemoryLayout<Int32>.size)
        #expect(getsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, &flagLength) == 0)
        #expect(noSigPipe == 1)

        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appending(path: "server.sock")
        let server = makeServer()
        server.start(at: path)
        var status = stat()
        #expect(lstat(path.path, &status) == 0)
        #expect(status.st_uid == getuid())
        #expect(status.st_mode & 0o777 == 0o600)
        #expect(status.st_mode & S_IFMT == S_IFSOCK)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test("teardown unlinks only the exact socket node")
    func exactNodeTeardown() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appending(path: "server.sock")
        let server = makeServer()
        server.start(at: path)
        #expect(MCPControlServer.identity(at: path) != nil)
        #expect(unlink(path.path) == 0)
        try Data("replacement".utf8).write(to: path)

        server.stop()
        #expect(try String(contentsOf: path, encoding: .utf8) == "replacement")
    }

    @Test("a trickling partial request cannot hold the server past one receive budget")
    func partialRequestReceiveBudget() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appending(path: "server.sock")
        let service = FakeKeepAwakeService()
        let server = makeServer(service: service)
        server.start(at: path)
        defer { server.stop() }

        let partialStarted = DispatchSemaphore(value: 0)
        let stopTrickle = DispatchSemaphore(value: 0)
        async let trickled = SocketTestClient.run {
            SocketTestClient.trickle(to: path.path, started: partialStarted, stop: stopTrickle)
        }
        let reply = await SocketTestClient.run {
            SocketTestClient.discover(at: path.path, after: partialStarted)
        }
        stopTrickle.signal()
        #expect(await trickled)

        let (line, elapsed) = try #require(reply)
        #expect(elapsed < .seconds(7))
        let response = try MCPControl.decoder().decode(MCPResponse.self, from: line)
        #expect(response.id == .string("after-partial"))
        #expect(response.error == nil)
        #expect(service.activationCount == 0)
    }

    private func makeServer(service: FakeKeepAwakeService = FakeKeepAwakeService()) -> MCPControlServer {
        let controller = SessionController(
            keepAwakeService: service,
            expiryScheduler: ManualExpiryScheduler()
        )
        return MCPControlServer(handler: MCPCommandHandler(controller: controller))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ut-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func makeSocket() -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        return descriptor >= 0 ? descriptor : nil
    }

    private func bindSocketNode(at path: URL, permissions: mode_t) throws {
        let descriptor = try #require(makeSocket())
        #expect(MCPControlServer.bindSocket(descriptor, path: path.path) == 0)
        close(descriptor)
        #expect(chmod(path.path, permissions) == 0)
    }
}

/// Blocking clients that run off the main actor so it stays free to serve requests.
/// Each call owns its descriptor and closes it before returning.
nonisolated private enum SocketTestClient {
    static let queue = DispatchQueue(label: "uptil.tests.socket-client", attributes: .concurrent)

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// Starts a mutating request, then sends one more byte per second without ever finishing the line.
    static func trickle(to path: String, started: DispatchSemaphore, stop: DispatchSemaphore) -> Bool {
        guard let descriptor = connect(to: path) else {
            started.signal()
            return false
        }
        defer { close(descriptor) }
        let prefix = "{\"jsonrpc\":\"2.0\",\"id\":\"partial\",\"method\":\"tools/call\"," +
            "\"params\":{\"name\":\"uptil.indefinite\","
        let sent = send(Data(prefix.utf8), to: descriptor)
        started.signal()
        guard sent else { return false }
        let giveUp = ContinuousClock.now + .seconds(12)
        while ContinuousClock.now < giveUp, stop.wait(timeout: .now() + 1) == .timedOut {
            guard send(Data(" ".utf8), to: descriptor) else { break }
        }
        return true
    }

    static func discover(at path: String, after partialStarted: DispatchSemaphore) -> (line: Data, elapsed: Duration)? {
        guard partialStarted.wait(timeout: .now() + 2) == .success else { return nil }
        let start = ContinuousClock.now
        guard let descriptor = connect(to: path, receiveTimeout: 8) else { return nil }
        defer { close(descriptor) }
        let request = MCPRequest(id: .string("after-partial"), method: "server/discover", params: .object([
            "_meta": .object([
                "io.modelcontextprotocol/protocolVersion": .string(MCPControl.protocolVersion),
                "io.modelcontextprotocol/clientCapabilities": .object([:]),
            ]),
        ]))
        guard
            let line = try? MCPFraming.line(for: MCPControl.encoder().encode(request)),
            send(line, to: descriptor)
        else { return nil }
        var response = Data()
        var byte: UInt8 = 0
        while read(descriptor, &byte, 1) == 1 {
            if byte == 0x0A {
                return (response, start.duration(to: .now))
            }
            response.append(byte)
        }
        return nil
    }

    private static func connect(to path: String, receiveTimeout seconds: Int = 5) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        guard
            MCPControlServer.configureSocket(descriptor),
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
            MCPControlServer.connectSocket(descriptor, path: path) == 0
        else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func send(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            return write(descriptor, base, bytes.count) == bytes.count
        }
    }
}
