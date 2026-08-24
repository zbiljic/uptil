import Foundation
import Testing
@testable import UpTilCore

@Suite("MCP newline framing")
struct MCPFramingTests {
    @Test("accepts one compact object and an LF")
    func objectLine() throws {
        let payload = Data("{\"jsonrpc\":\"2.0\"}".utf8)
        let line = try MCPFraming.line(for: payload)
        #expect(line.last == 0x0A)
        #expect(try MCPFraming.objectData(from: line) == payload)
    }

    @Test("rejects malformed bounded frames")
    func malformedFrames() throws {
        #expect(throws: MCPFramingError.self) { try MCPFraming.line(for: Data()) }
        #expect(throws: MCPFramingError.self) { try MCPFraming.line(for: Data("{}\r".utf8)) }
        #expect(throws: MCPFramingError.self) { try MCPFraming.line(for: Data("{}\n".utf8)) }
        #expect(throws: MCPFramingError.self) { try MCPFraming.objectData(from: Data("[]\n".utf8)) }
        #expect(throws: MCPFramingError.self) { try MCPFraming.objectData(from: Data([0xFF, 0x0A])) }
        #expect(throws: MCPFramingError.self) { try MCPFraming.line(for: Data(
            repeating: 0x20,
            count: MCPFraming.maximumLineBytes + 1
        )) }
        let maximumObject = Data(("{\"value\":\"" + String(
            repeating: "a",
            count: MCPFraming.maximumLineBytes - 12
        ) + "\"}").utf8)
        #expect(maximumObject.count == MCPFraming.maximumLineBytes)
        #expect(try MCPFraming.objectData(from: MCPFraming.line(for: maximumObject)) == maximumObject)
    }

    @Test("sequential frames and EOF-before-LF remain distinct")
    func sequentialFrames() throws {
        #expect(try MCPFraming.objectData(from: Data("{}\n".utf8)) == Data("{}".utf8))
        #expect(try MCPFraming.objectData(from: Data("{\"a\":1}\n".utf8)) == Data("{\"a\":1}".utf8))
        #expect(throws: MCPFramingError.self) { try MCPFraming.objectData(from: Data("{\"a\":1".utf8)) }
    }
}
