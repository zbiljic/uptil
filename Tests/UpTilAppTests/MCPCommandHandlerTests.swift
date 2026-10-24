import Foundation
import Testing
@testable import UpTil
import UpTilCore

@MainActor
@Suite("MCP command handler")
struct MCPCommandHandlerTests {
    @Test("discovery and list expose the modern six-tool surface")
    func discoveryAndList() throws {
        let fixture = Fixture()
        let discovery = try fixture.response(method: "server/discover")
        let discoveryBody = discovery.result?.objectValue
        #expect(discoveryBody?["supportedVersions"] == .array([.string(MCPControl.protocolVersion)]))
        #expect(discoveryBody?["resultType"] == .string("complete"))
        #expect(discoveryBody?["ttlMs"] == .number(0))
        #expect(discoveryBody?["cacheScope"] == .string("private"))
        #expect(discoveryBody?["protocolVersion"] == nil)
        #expect(discoveryBody?["serverInfo"] == nil)
        let expectedServerInfo: JSONValue = .object([
            "name": .string(MCPControl.serverName), "version": .string(MCPControl.serverVersion),
        ])
        #expect(discoveryBody?["_meta"]?.objectValue?["io.modelcontextprotocol/serverInfo"] == expectedServerInfo)
        #expect(discoveryBody?["capabilities"] == .object(["tools": .object([:])]))

        let list = try fixture.response(method: "tools/list")
        let tools = list.result?.objectValue?["tools"]
        guard case let .array(values)? = tools else { Issue.record("missing tools"); return }
        #expect(values.compactMap { $0.objectValue?["name"] }.map { value in
            if case let .string(name) = value {
                return name
            }; return ""
        } == MCPTool.allCases.map(\.rawValue))
        #expect(list.result?.objectValue?["resultType"] == .string("complete"))
        #expect(list.result?.objectValue?["ttlMs"] == .number(300_000))
        #expect(list.result?.objectValue?["cacheScope"] == .string("public"))
        #expect(list.result?.objectValue?["_meta"]?.objectValue?["io.modelcontextprotocol/serverInfo"] ==
            expectedServerInfo)
    }

    @Test("mutations use controller and return authoritative snapshots")
    func mutations() throws {
        let fixture = Fixture()
        #expect(try fixture.tool("uptil.start", arguments: ["durationSeconds": .number(60)]).isError == false)
        #expect(fixture.controller.session == .timed(deadline: fixture.date.addingTimeInterval(60)))
        #expect(try fixture.tool("uptil.extend", arguments: ["durationSeconds": .number(30)]).isError == false)
        #expect(try fixture.tool("uptil.shorten", arguments: ["durationSeconds": .number(20)]).isError == false)
        #expect(try fixture.tool("uptil.indefinite").isError == false)
        #expect(fixture.controller.session == .indefinite)
        #expect(try fixture.tool("uptil.stop").isError == false)
        #expect(fixture.controller.session == .idle)
        #expect(fixture.service.activationCount == 1)
        #expect(fixture.service.deactivationCount == 1)

        let status = try fixture.tool("uptil.status")
        #expect(status.structured?.objectValue?["state"] == .string("idle"))
        #expect(status.structured?.objectValue?["pid"] == .number(77))
        #expect(status.text == "Idle.")
        expectLiveStatus(status.structured)
    }

    @Test("rejected requests preserve state and accept omitted client info")
    func rejectionAndMetadata() throws {
        let fixture = Fixture()
        let before = fixture.controller.session
        let invalid = try fixture.tool("uptil.extend", arguments: ["durationSeconds": .number(60)])
        #expect(invalid.isError)
        #expect(fixture.controller.session == before)
        #expect(try fixture.response(method: "tools/list", includeClientInfo: false).error == nil)
        #expect(try fixture.response(method: "tools/list", suppliedMetadata: [:]).error?.code == -32600)
        #expect(try fixture.response(
            method: "tools/list",
            suppliedMetadata: ["io.modelcontextprotocol/protocolVersion": .string(MCPControl.protocolVersion)]
        ).error?.code == -32600)
        #expect(try fixture.response(
            method: "tools/list",
            suppliedMetadata: [
                "io.modelcontextprotocol/protocolVersion": .number(1),
                "io.modelcontextprotocol/clientCapabilities": .object([:]),
            ]
        ).error?.code == -32600)
        let unsupported = try fixture.response(method: "tools/list", version: "2025-11-25")
        #expect(unsupported.error?.code == -32022)
        #expect(unsupported.error?.data == .object([
            "supported": .array([.string(MCPControl.protocolVersion)]),
            "requested": .string("2025-11-25"),
        ]))
    }

    @Test("stale state refreshes before status and rejected calls do not mutate lifecycle")
    func refreshAndRejectedCalls() throws {
        let fixture = Fixture()
        #expect(fixture.controller.start(for: 1))
        fixture.date = fixture.date.addingTimeInterval(2)
        let refreshed = try fixture.tool("uptil.status")
        #expect(refreshed.structured?.objectValue?["state"] == .string("idle"))
        #expect(fixture.service.deactivationCount == 1)

        let activationCount = fixture.service.activationCount
        let deactivationCount = fixture.service.deactivationCount
        for arguments: [String: JSONValue] in [
            [:],
            ["durationSeconds": .number(0)],
            ["durationSeconds": .number(-1)],
            ["durationSeconds": .string("60")],
            ["durationSeconds": .number(60), "extra": .bool(true)],
        ] {
            #expect(try fixture.tool("uptil.start", arguments: arguments).isError)
        }
        #expect(try fixture.response(method: "tools/call", tool: "unknown").error?.code == -32602)
        let invalidArguments = try fixture.response(
            method: "tools/call",
            tool: "uptil.status",
            argumentsValue: .string("invalid")
        )
        #expect(invalidArguments.error?.code == -32602)
        #expect(fixture.controller.session == .idle)
        #expect(fixture.service.activationCount == activationCount)
        #expect(fixture.service.deactivationCount == deactivationCount)
    }

    @Test("overflowing duration results are rejected without changing state")
    func overflow() throws {
        let fixture = Fixture()
        let hugeStart = try fixture.tool("uptil.start", arguments: [
            "durationSeconds": .number(Double.greatestFiniteMagnitude),
        ])
        #expect(hugeStart.isError)
        #expect(fixture.controller.session == .idle)
        let deadline = fixture.controller.session.deadline
        #expect(try fixture.tool("uptil.extend", arguments: [
            "durationSeconds": .number(Double.greatestFiniteMagnitude),
        ]).isError)
        #expect(fixture.controller.session.deadline == deadline)
    }

    @Test("transition rejections preserve flat status and explain the failed precondition")
    func transitionRejections() throws {
        let fixture = Fixture()
        let missingTimed = try fixture.tool("uptil.shorten", arguments: ["durationSeconds": .number(1)])
        #expect(missingTimed.isError)
        #expect(missingTimed.text == "Cannot shorten: a timed session is required.")
        expectLiveStatus(missingTimed.structured)
        #expect(fixture.controller.session == .idle)

        let started = try fixture.tool("uptil.start", arguments: ["durationSeconds": .number(10)])
        let until = started.structured?.objectValue?["until"]
        if case let .string(renderedUntil)? = until {
            #expect(started.text == "Started a timed session until \(renderedUntil).")
        } else {
            Issue.record("missing timed until")
        }
        let before = fixture.controller.session
        let throughNow = try fixture.tool("uptil.shorten", arguments: ["durationSeconds": .number(10)])
        #expect(throughNow.isError)
        #expect(throughNow.text == "Cannot shorten: it would reach or pass now.")
        #expect(throughNow.text != missingTimed.text)
        expectLiveStatus(throughNow.structured)
        #expect(fixture.controller.session == before)
    }

    @Test("errors echo IDs and notifications are silent")
    func idsAndNotifications() throws {
        let fixture = Fixture()
        let unknown = try fixture.response(method: "missing", id: .string("same"))
        #expect(unknown.id == .string("same"))
        #expect(unknown.error?.code == -32601)
        let numeric = try fixture.response(method: "missing", id: .number(17))
        #expect(numeric.id == .number(17))
        #expect(numeric.error?.code == -32601)
        #expect(fixture.raw(method: "tools/list", id: nil) == nil)
        #expect(fixture.notification(tool: "uptil.indefinite") == nil)
        for rawID in ["1.5", "9223372036854775808", "true", "[]", "{}", "null"] {
            let response = try fixture.response(method: "tools/call", rawID: rawID, tool: "uptil.indefinite")
            #expect(response.id == nil)
            #expect(response.error?.code == -32600)
        }
        #expect(fixture.controller.session == .idle)
        #expect(fixture.service.activationCount == 0)
        let batch = fixture.handler.response(for: Data("[]".utf8))
        #expect(try MCPControl.decoder().decode(MCPResponse.self, from: batch ?? Data()).error?.code == -32600)
        let malformed = fixture.handler.response(for: Data("{".utf8))
        #expect(try MCPControl.decoder().decode(MCPResponse.self, from: malformed ?? Data()).error?.code == -32700)
        let primitive = fixture.handler.response(for: Data("1".utf8))
        #expect(try MCPControl.decoder().decode(MCPResponse.self, from: primitive ?? Data()).error?.code == -32600)
    }

    @Test("integer IDs beyond Double precision echo exactly")
    func exactIntegerIDs() throws {
        let fixture = Fixture()
        let discovery = try fixture.response(method: "server/discover", rawID: "9007199254740993")
        #expect(discovery.id == .number(9_007_199_254_740_993))
        #expect(discovery.error == nil)
        let unknown = try fixture.response(method: "missing", rawID: "9007199254740993")
        #expect(unknown.id == .number(9_007_199_254_740_993))
        #expect(unknown.error?.code == -32601)
        #expect(try fixture.tool("uptil.start", arguments: ["durationSeconds": .number(1.5)]).isError == false)
        #expect(fixture.controller.session == .timed(deadline: fixture.date.addingTimeInterval(1.5)))
    }

    @Test("paused sessions report frozen status, reject adjustments, and can be replaced or stopped")
    func pausedSessions() throws {
        let fixture = Fixture()
        #expect(fixture.controller.start(for: 720))
        #expect(fixture.controller.pause())
        fixture.date = fixture.date.addingTimeInterval(3600)

        let status = try fixture.tool("uptil.status")
        #expect(status.text == "Paused with 12m remaining.")
        #expect(status.structured == .object([
            "schemaVersion": .number(1), "state": .string("paused"), "assertionActive": .bool(false),
            "remainingSeconds": .number(720), "pid": .number(77),
        ]))
        expectLiveStatus(status.structured)
        for (tool, message) in [
            ("uptil.extend", "Cannot extend: the session is paused."),
            ("uptil.shorten", "Cannot shorten: the session is paused."),
        ] {
            let rejected = try fixture.tool(tool, arguments: ["durationSeconds": .number(60)])
            #expect(rejected.isError)
            #expect(rejected.text == message)
            #expect(rejected.structured?.objectValue?["state"] == .string("paused"))
        }
        #expect(fixture.controller.session == .paused(remaining: 720))

        #expect(try fixture.tool("uptil.start", arguments: ["durationSeconds": .number(60)]).isError == false)
        #expect(fixture.controller.session == .timed(deadline: fixture.date.addingTimeInterval(60)))
        #expect(fixture.controller.pause())
        #expect(try fixture.tool("uptil.indefinite").isError == false)
        #expect(fixture.controller.session == .indefinite)
        #expect(fixture.controller.start(for: 60))
        #expect(fixture.controller.pause())
        #expect(try fixture.tool("uptil.stop").isError == false)
        #expect(fixture.controller.session == .idle)
        #expect(fixture.service.activationCount == 3)
        #expect(fixture.service.deactivationCount == 3)
    }

    @Test("status uses one clock snapshot for refresh and rendering")
    func consistentStatusSnapshot() throws {
        let fixture = Fixture()
        #expect(fixture.controller.start(for: 0.5))
        fixture.nowReadIncrement = 1
        let status = try fixture.tool("uptil.status").structured?.objectValue
        #expect(status?["state"] == .string("timed"))
        #expect(status?["until"] == .string("2001-01-01T00:16:40Z"))
        #expect(fixture.date == Date(timeIntervalSinceReferenceDate: 1001))
    }

    @Test("rate limiter has a deterministic burst and refill")
    func rateLimit() throws {
        let fixture = Fixture()
        for _ in 0 ..< 40 {
            #expect(try fixture.response(method: "tools/call", tool: "uptil.status").error == nil)
        }
        let limited = try fixture.response(method: "tools/call", tool: "uptil.status")
        #expect(limited.error?.code == -32603)
        #expect(limited.error?.message == "Tool rate limit exceeded; retry shortly.")
        fixture.rate += 0.05
        #expect(try fixture.response(method: "tools/call", tool: "uptil.status").error == nil)
        #expect(fixture.controller.session == .idle)
    }
}

@MainActor
private final class Fixture {
    var date = Date(timeIntervalSinceReferenceDate: 1000)
    var nowReadIncrement: TimeInterval = 0
    let service = FakeKeepAwakeService()
    let scheduler = ManualExpiryScheduler()
    var rate: TimeInterval = 0
    lazy var controller = SessionController(keepAwakeService: service, expiryScheduler: scheduler) { self.date }
    lazy var handler = MCPCommandHandler(
        controller: controller,
        now: {
            let result = self.date
            self.date = self.date.addingTimeInterval(self.nowReadIncrement)
            return result
        },
        pid: { 77 },
        rateNow: { self.rate }
    )

    func tool(_ name: String, arguments: [String: JSONValue] = [:]) throws -> ToolResult {
        let response = try response(method: "tools/call", tool: name, arguments: arguments)
        guard let result = response.result?.objectValue else { throw NSError(domain: "test", code: 1) }
        let structured = result["structuredContent"]
        return ToolResult(
            isError: result["isError"] == .bool(true),
            structured: structured,
            text: textContent(in: result)
        )
    }

    private func textContent(in result: [String: JSONValue]) -> String? {
        guard case let .array(content)? = result["content"] else { return nil }
        guard case let .object(first)? = content.first else { return nil }
        guard case let .string(text)? = first["text"] else { return nil }
        return text
    }

    func response(
        method: String,
        id: MCPRequestID? = .string("id"),
        tool: String? = nil,
        arguments: [String: JSONValue] = [:],
        argumentsValue: JSONValue? = nil,
        includeClientInfo: Bool = true,
        version: String = MCPControl.protocolVersion,
        suppliedMetadata: [String: JSONValue]? = nil
    ) throws -> MCPResponse {
        let meta = suppliedMetadata ?? makeMetadata(includeClientInfo: includeClientInfo, version: version)
        var params: [String: JSONValue] = ["_meta": .object(meta)]
        if let tool {
            params["name"] = .string(tool)
            params["arguments"] = argumentsValue ?? .object(arguments)
        }
        guard
            let data = raw(method: method, id: id, params: params), let response = try? MCPControl.decoder().decode(
                MCPResponse.self,
                from: data
            )
        else {
            throw NSError(domain: "test", code: 2)
        }
        return response
    }

    /// Splices `rawID` into the request text unchanged, so the codec sees the ID exactly as a client wrote it.
    func response(method: String, rawID: String, tool: String? = nil) throws -> MCPResponse {
        var params: [String: JSONValue] = [
            "_meta": .object(makeMetadata(includeClientInfo: true, version: MCPControl.protocolVersion)),
        ]
        if let tool {
            params["name"] = .string(tool)
            params["arguments"] = .object([:])
        }
        let paramsData = try MCPControl.encoder().encode(JSONValue.object(params))
        guard
            let encodedParams = String(bytes: paramsData, encoding: .utf8),
            let data = handler.response(for: Data(
                "{\"jsonrpc\":\"2.0\",\"id\":\(rawID),\"method\":\"\(method)\",\"params\":\(encodedParams)}".utf8
            ))
        else {
            throw NSError(domain: "test", code: 3)
        }
        return try MCPControl.decoder().decode(MCPResponse.self, from: data)
    }

    func raw(method: String, id: MCPRequestID?, params: [String: JSONValue] = [:]) -> Data? {
        handler.response(for: (try? MCPControl.encoder().encode(MCPRequest(
            id: id,
            method: method,
            params: .object(params)
        ))) ?? Data())
    }

    func notification(tool: String) -> Data? {
        raw(method: "tools/call", id: nil, params: [
            "name": .string(tool),
            "arguments": .object([:]),
            "_meta": .object(makeMetadata(includeClientInfo: true, version: MCPControl.protocolVersion)),
        ])
    }

    private func makeMetadata(includeClientInfo: Bool, version: String) -> [String: JSONValue] {
        var value: [String: JSONValue] = [
            "io.modelcontextprotocol/protocolVersion": .string(version),
            "io.modelcontextprotocol/clientCapabilities": .object([:]),
        ]
        if includeClientInfo {
            value["io.modelcontextprotocol/clientInfo"] = .object(["name": .string("test")])
        }
        return value
    }
}

private struct ToolResult {
    let isError: Bool
    let structured: JSONValue?
    let text: String?
}

private func expectLiveStatus(_ status: JSONValue?) {
    guard let object = status?.objectValue else {
        Issue.record("missing flat status")
        return
    }
    let isPaused = object["state"] == .string("paused")
    for removed in [
        "apiVersion", "appRunning", "status", "kind", "deadline", "deadlineEpochSeconds", "remainingSeconds", "appPID",
        "problem", "type", "title", "detail", "code", "reason", "domain", "category", "errorCategory",
    ] where !(isPaused && removed == "remainingSeconds") {
        #expect(object[removed] == nil)
    }
}
