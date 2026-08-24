import Darwin
import Foundation
import UpTilCore

enum MCPControlClientError: Error {
    case unavailable
    case requestMayHaveBeenSent(String)
    case responseTimeout
    case responseEOF
    case responseTooLarge
    case invalidResponseFraming
    case invalidResponseJSON
    case invalidResponseEnvelope
    case failed(String)
}

struct MCPControlClient {
    func send(_ request: MCPRequest) throws -> MCPResponse {
        let response: MCPResponse
        do {
            response = try MCPControl.decoder().decode(
                MCPResponse.self,
                from: sendRaw(MCPControl.encoder().encode(request))
            )
        } catch is DecodingError {
            throw MCPControlClientError.invalidResponseJSON
        }
        guard response.isValid, response.id == request.id else {
            throw MCPControlClientError.invalidResponseEnvelope
        }
        return response
    }

    func sendRaw(_ data: Data) throws -> Data {
        guard
            let path = ControlSocketPath.socketURL(
                home: FileManager.default.homeDirectoryForCurrentUser,
                runningInsideContainer: false
            ) else { throw MCPControlClientError.unavailable }
        var status = stat()
        guard
            lstat(path.path, &status) == 0, (status.st_mode & S_IFMT) == S_IFSOCK,
            status.st_uid == getuid(), status.st_mode & 0o777 == 0o600
        else { throw MCPControlClientError.unavailable }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MCPControlClientError.failed("Unable to create socket.") }
        defer { close(descriptor) }
        guard configureSocket(descriptor) else {
            throw MCPControlClientError.failed("Unable to configure socket timeouts.")
        }
        guard connectSocket(descriptor, path: path.path) == 0 else { throw MCPControlClientError.unavailable }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard
            getpeereid(descriptor, &uid, &gid) == 0,
            uid == getuid()
        else { throw MCPControlClientError.failed("Socket peer identity did not match the current user.") }
        let line = try MCPFraming.line(for: data)
        switch writeAll(descriptor, line) {
        case .complete: break
        case .none: throw MCPControlClientError.failed("The request could not be sent.")
        case .partial: throw MCPControlClientError.requestMayHaveBeenSent("The request may have reached UpTil.")
        }
        return try readLine(descriptor)
    }

    private func connectSocket(_ descriptor: Int32, path: String) -> Int32 {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(
            descriptor,
            $0,
            socklen_t(MemoryLayout<sockaddr_un>.size)
        ) } }
    }

    private enum WriteOutcome { case complete, none, partial }

    private func writeAll(_ descriptor: Int32, _ data: Data) -> WriteOutcome {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return write(descriptor, baseAddress.advanced(by: offset), data.count - offset)
            }
            if written < 0, errno == EINTR {
                continue
            }
            guard written > 0 else { return offset == 0 ? .none : .partial }
            offset += written
        }
        return .complete
    }

    private func readLine(_ descriptor: Int32) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0
        while data.count <= MCPFraming.maximumLineBytes {
            let count = read(descriptor, &byte, 1)
            if count < 0, errno == EINTR {
                continue
            }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                throw MCPControlClientError.responseTimeout
            }
            if count == 0 {
                throw MCPControlClientError.responseEOF
            }
            guard count == 1 else { throw MCPControlClientError.invalidResponseFraming }
            data.append(byte)
            if byte == 0x0A {
                do {
                    return try MCPFraming.objectData(from: data)
                } catch {
                    throw MCPControlClientError.invalidResponseFraming
                }
            }
        }
        throw MCPControlClientError.responseTooLarge
    }

    private func configureSocket(_ descriptor: Int32) -> Bool {
        var noSigPipe: Int32 = 1
        guard
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            ) == 0 else { return false }
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
}
