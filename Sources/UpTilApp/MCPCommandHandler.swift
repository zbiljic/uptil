import Foundation
import UpTilCore

@MainActor
final class MCPCommandHandler {
    private let controller: SessionController
    private let now: @MainActor () -> Date
    private let pid: @MainActor () -> Int32
    private let rateNow: @MainActor () -> TimeInterval
    private var availableTokens: Double = 40
    private var lastTokenTime: TimeInterval

    init(
        controller: SessionController,
        now: @escaping @MainActor () -> Date = { Date() },
        pid: @escaping @MainActor () -> Int32 = { ProcessInfo.processInfo.processIdentifier },
        rateNow: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.controller = controller
        self.now = now
        self.pid = pid
        self.rateNow = rateNow
        lastTokenTime = rateNow()
    }

    func response(for data: Data) -> Data? {
        switch decodeRequest(data) {
        case let .request(request):
            response(for: request)
        case let .error(error):
            encoded(MCPResponse(id: nil, error: error))
        }
    }

    private enum RequestDecoding {
        case request(MCPRequest)
        case error(MCPError)
    }

    private func decodeRequest(_ data: Data) -> RequestDecoding {
        guard let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return .error(MCPError(code: -32700, message: "Parse error"))
        }
        if value is [Any] {
            return .error(MCPError(code: -32600, message: "Batch requests are not supported."))
        }
        guard value is [String: Any] else {
            return .error(MCPError(code: -32600, message: "Invalid request"))
        }
        guard let request = try? MCPControl.decoder().decode(MCPRequest.self, from: data) else {
            return .error(MCPError(code: -32600, message: "Invalid request"))
        }
        return .request(request)
    }

    private func response(for request: MCPRequest) -> Data? {
        guard request.jsonrpc == "2.0" else {
            return response(for: request, error: MCPError(code: -32600, message: "Invalid JSON-RPC version"))
        }
        guard request.hasValidID else {
            return encoded(MCPResponse(id: nil, error: MCPError(code: -32600, message: "Invalid JSON-RPC ID")))
        }
        guard !request.isNotification else { return nil }
        guard let requestedVersion = validateMetadata(request.params) else {
            return response(for: request, error: MCPError(code: -32600, message: "Missing or invalid MCP metadata"))
        }
        if requestedVersion != MCPControl.protocolVersion {
            return response(for: request, error: MCPError(
                code: -32022,
                message: "Unsupported protocol version",
                data: .object([
                    "supported": .array([.string(MCPControl.protocolVersion)]),
                    "requested": .string(requestedVersion),
                ])
            ))
        }

        switch dispatch(request) {
        case let .result(result):
            return response(for: request, result: result)
        case let .error(error):
            return response(for: request, error: error)
        }
    }

    private func dispatch(_ request: MCPRequest) -> ToolDispatch {
        switch request.method {
        case "server/discover":
            return .result(.object([
                "supportedVersions": .array([.string(MCPControl.protocolVersion)]),
                "capabilities": .object(["tools": .object([:])]),
                "resultType": .string("complete"),
                "ttlMs": .number(0),
                "cacheScope": .string("private"),
                "_meta": .object(["io.modelcontextprotocol/serverInfo": serverInfo]),
            ]))
        case "tools/list":
            return .result(.object([
                "tools": .array(MCPTool.allCases.map(toolDefinition)),
                "resultType": .string("complete"),
                "ttlMs": .number(300_000),
                "cacheScope": .string("public"),
                "_meta": .object(["io.modelcontextprotocol/serverInfo": serverInfo]),
            ]))
        case "tools/call":
            guard consumeToolToken() else {
                return .error(MCPError(
                    code: -32603,
                    message: "Tool rate limit exceeded; retry shortly."
                ))
            }
            return callTool(request.params)
        default:
            return .error(MCPError(code: -32601, message: "Method not found"))
        }
    }

    private var serverInfo: JSONValue {
        .object(["name": .string(MCPControl.serverName), "version": .string(MCPControl.serverVersion)])
    }

    private func validateMetadata(_ params: JSONValue?) -> String? {
        guard
            let metadata = params?.objectValue?["_meta"]?.objectValue,
            case let .string(version)? = metadata["io.modelcontextprotocol/protocolVersion"],
            metadata["io.modelcontextprotocol/clientCapabilities"]?.objectValue != nil
        else { return nil }
        return version
    }

    private func toolDefinition(_ tool: MCPTool) -> JSONValue {
        .object([
            "name": .string(tool.rawValue),
            "description": .string(tool.description),
            "inputSchema": tool.schema,
            "outputSchema": MCPTool.statusOutputSchema,
            "annotations": .object([
                "readOnlyHint": .bool(tool == .status),
                "idempotentHint": .bool(tool == .status || tool == .stop),
                "destructiveHint": .bool(false),
                "openWorldHint": .bool(false),
            ]),
        ])
    }
}

private extension MCPCommandHandler {
    private enum ToolDispatch {
        case result(JSONValue)
        case error(MCPError)
    }

    private enum ToolCallDecoding {
        case call(MCPTool, [String: JSONValue])
        case error(MCPError)
    }

    private func decodeToolCall(_ params: JSONValue?) -> ToolCallDecoding {
        guard
            let object = params?.objectValue,
            case let .string(name)? = object["name"], let tool = MCPTool(rawValue: name)
        else {
            return .error(MCPError(code: -32602, message: "Unknown tool."))
        }
        guard let suppliedArguments = object["arguments"] else {
            return .error(MCPError(code: -32602, message: "tools/call requires arguments."))
        }
        guard let arguments = suppliedArguments.objectValue else {
            return .error(MCPError(code: -32602, message: "tools/call arguments must be an object."))
        }
        return .call(tool, arguments)
    }

    private func callTool(_ params: JSONValue?) -> ToolDispatch {
        let tool: MCPTool
        let arguments: [String: JSONValue]
        switch decodeToolCall(params) {
        case let .call(decodedTool, decodedArguments):
            tool = decodedTool
            arguments = decodedArguments
        case let .error(error):
            return .error(error)
        }

        let currentDate = now()
        controller.refresh(at: currentDate)
        return execute(tool, arguments: arguments, at: currentDate)
    }

    private func execute(
        _ tool: MCPTool,
        arguments: [String: JSONValue],
        at currentDate: Date
    ) -> ToolDispatch {
        let result: Bool
        switch tool {
        case .status:
            result = arguments.isEmpty
        case .indefinite:
            result = arguments.isEmpty
            if result {
                controller.startIndefinitely()
            }
        case .stop:
            result = arguments.isEmpty
            if result {
                controller.stop()
            }
        case .start, .extend, .shorten:
            return executeDurationTool(tool, arguments: arguments, at: currentDate)
        }
        return completed(tool, succeeded: result, at: currentDate)
    }

    private func executeDurationTool(
        _ tool: MCPTool,
        arguments: [String: JSONValue],
        at currentDate: Date
    ) -> ToolDispatch {
        guard
            arguments.count == 1,
            case let .number(duration)? = arguments["durationSeconds"],
            duration.isFinite,
            duration > 0,
            durationFits(tool, duration: duration, at: currentDate)
        else {
            return .result(toolError("durationSeconds must be one positive finite number.", at: currentDate))
        }

        let result: Bool
        switch tool {
        case .start:
            result = controller.start(for: duration)
        case .extend:
            guard !controller.session.isPaused else {
                return .result(toolError("Cannot extend: the session is paused.", at: currentDate))
            }
            guard case .timed = controller.session else {
                return .result(toolError("Cannot extend: a timed session is required.", at: currentDate))
            }
            result = controller.extend(by: duration)
        case .shorten:
            guard !controller.session.isPaused else {
                return .result(toolError("Cannot shorten: the session is paused.", at: currentDate))
            }
            guard let deadline = controller.session.deadline else {
                return .result(toolError("Cannot shorten: a timed session is required.", at: currentDate))
            }
            guard deadline.addingTimeInterval(-duration) > currentDate else {
                return .result(toolError("Cannot shorten: it would reach or pass now.", at: currentDate))
            }
            result = controller.shorten(by: duration)
        case .status, .indefinite, .stop:
            return .result(toolError("This operation is not valid for the current session.", at: currentDate))
        }
        return completed(tool, succeeded: result, at: currentDate)
    }

    private func completed(_ tool: MCPTool, succeeded: Bool, at currentDate: Date) -> ToolDispatch {
        guard succeeded else {
            return .result(toolError("This operation is not valid for the current session.", at: currentDate))
        }
        return .result(toolSuccess(successText(for: tool, at: currentDate), at: currentDate))
    }

    private func successText(for tool: MCPTool, at currentDate: Date) -> String {
        switch tool {
        case .status: statusValue(at: currentDate).text
        case .start: "Started a timed session until \(statusValue(at: currentDate).until.flatMap(MCPControl.rfc3339String) ?? "")."
        case .indefinite: "Started an indefinite session."
        case .extend: "Extended the timed session until \(statusValue(at: currentDate).until.flatMap(MCPControl.rfc3339String) ?? "")."
        case .shorten: "Shortened the timed session until \(statusValue(at: currentDate).until.flatMap(MCPControl.rfc3339String) ?? "")."
        case .stop: "Stopped the session."
        }
    }

    private func durationFits(_ tool: MCPTool, duration: TimeInterval, at currentDate: Date) -> Bool {
        switch tool {
        case .start:
            deadlineFits(currentDate.addingTimeInterval(duration))
        case .extend:
            controller.session.deadline.map { deadlineFits($0.addingTimeInterval(duration)) } ?? true
        case .shorten:
            controller.session.deadline.map { deadlineFits($0.addingTimeInterval(-duration)) } ?? true
        case .status, .indefinite, .stop:
            true
        }
    }

    private func deadlineFits(_ deadline: Date) -> Bool {
        deadline.timeIntervalSinceReferenceDate.isFinite && MCPControl.rfc3339String(deadline) != nil
    }

    private func toolSuccess(_ text: String, at currentDate: Date) -> JSONValue {
        let status = statusJSON(at: currentDate)
        return .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "structuredContent": status,
            "isError": .bool(false),
            "resultType": .string("complete"),
            "_meta": .object(["io.modelcontextprotocol/serverInfo": serverInfo]),
        ])
    }

    private func toolError(_ message: String, at currentDate: Date) -> JSONValue {
        let status = statusJSON(at: currentDate)
        return .object([
            "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
            "structuredContent": status,
            "isError": .bool(true),
            "resultType": .string("complete"),
            "_meta": .object(["io.modelcontextprotocol/serverInfo": serverInfo]),
        ])
    }

    private func statusValue(at _: Date) -> UpTilLiveStatus {
        let session = controller.session
        return switch session {
        case .idle:
            .idle(pid: pid())
        case .indefinite:
            .indefinite(pid: pid())
        case let .timed(deadline):
            .timed(until: deadline, pid: pid())
        case let .paused(remaining):
            .paused(remaining: remaining, pid: pid())
        }
    }

    private func statusJSON(at current: Date) -> JSONValue {
        let data = (try? MCPControl.encoder().encode(statusValue(at: current))) ?? Data("{}".utf8)
        return (try? MCPControl.decoder().decode(JSONValue.self, from: data)) ?? .object([:])
    }

    private func response(for request: MCPRequest, result: JSONValue) -> Data? {
        guard !request.isNotification else { return nil }
        return encoded(MCPResponse(id: request.id, result: result))
    }

    private func response(for request: MCPRequest, error: MCPError) -> Data? {
        guard !request.isNotification else { return nil }
        return encoded(MCPResponse(id: request.id, error: error))
    }

    private func encoded(_ response: MCPResponse) -> Data? {
        try? MCPControl.encoder().encode(response)
    }

    private func consumeToolToken() -> Bool {
        let current = rateNow()
        let elapsed = max(0, current - lastTokenTime)
        availableTokens = min(40, availableTokens + elapsed * 20)
        lastTokenTime = current
        guard availableTokens >= 1 else { return false }
        availableTokens -= 1
        return true
    }
}
