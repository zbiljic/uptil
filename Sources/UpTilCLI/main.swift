import Darwin
import Foundation
import UpTilCore

// swiftlint:disable line_length
let usage = """
Usage: uptil status [--json] | start <duration> | indefinite | extend <duration> | shorten <duration> | stop | mcp | version | help
Duration: a positive number followed by s, m, or h (for example 30s, 15m, 1.5h).
"""
// swiftlint:enable line_length

func metadata() -> JSONValue {
    .object([
        "io.modelcontextprotocol/protocolVersion": .string(MCPControl.protocolVersion),
        "io.modelcontextprotocol/clientCapabilities": .object([:]),
        "io.modelcontextprotocol/clientInfo": .object([
            "name": .string("uptil-cli"),
            "version": .string(MCPControl.serverVersion),
        ]),
    ])
}

func callRequest(tool: MCPTool, arguments: JSONValue = .object([:])) -> MCPRequest {
    MCPRequest(
        id: .string(UUID().uuidString),
        method: "tools/call",
        params: .object(["name": .string(tool.rawValue), "arguments": arguments, "_meta": metadata()])
    )
}

struct HumanInvocation {
    let tool: MCPTool
    let arguments: JSONValue
    let jsonOnly: Bool

    init?(_ command: UpTilCommand) {
        switch command {
        case let .status(json):
            tool = .status
            arguments = .object([:])
            jsonOnly = json
        case let .start(duration):
            tool = .start
            arguments = Self.durationArguments(duration)
            jsonOnly = false
        case .indefinite:
            tool = .indefinite
            arguments = .object([:])
            jsonOnly = false
        case let .extend(duration):
            tool = .extend
            arguments = Self.durationArguments(duration)
            jsonOnly = false
        case let .shorten(duration):
            tool = .shorten
            arguments = Self.durationArguments(duration)
            jsonOnly = false
        case .stop:
            tool = .stop
            arguments = .object([:])
            jsonOnly = false
        default:
            return nil
        }
    }

    private static func durationArguments(_ duration: TimeInterval) -> JSONValue {
        .object(["durationSeconds": .number(duration)])
    }
}

func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

func postSendFailure(_ message: String, mutates: Bool) -> Int32 {
    if mutates {
        writeError("\(message) The outcome is unknown; run `uptil status`.")
        return 4
    }
    writeError(message)
    return 1
}

func handleClientError(_ error: Error, invocation: HumanInvocation) -> Int32 {
    switch error {
    case MCPControlClientError.unavailable:
        if invocation.jsonOnly {
            print("{\"schemaVersion\":1,\"state\":\"unavailable\"}")
        } else {
            writeError("UpTil is not running or its control socket is unavailable.")
        }
        return 3
    case MCPControlClientError.requestMayHaveBeenSent:
        return postSendFailure("UpTil did not receive the complete request.", mutates: invocation.tool != .status)
    case MCPControlClientError.responseTimeout:
        return postSendFailure(
            "UpTil timed out before returning a complete response.",
            mutates: invocation.tool != .status
        )
    case MCPControlClientError.responseEOF:
        return postSendFailure(
            "UpTil closed the connection before returning a complete response.",
            mutates: invocation.tool != .status
        )
    case MCPControlClientError.responseTooLarge:
        return postSendFailure("UpTil returned an oversized response.", mutates: invocation.tool != .status)
    case MCPControlClientError.invalidResponseFraming:
        return postSendFailure("UpTil returned invalid response framing.", mutates: invocation.tool != .status)
    case MCPControlClientError.invalidResponseJSON:
        return postSendFailure("UpTil returned invalid response JSON.", mutates: invocation.tool != .status)
    case MCPControlClientError.invalidResponseEnvelope:
        return postSendFailure(
            "UpTil returned a response with an unexpected ID or envelope.",
            mutates: invocation.tool != .status
        )
    default:
        writeError("uptil: \(error)")
        return 1
    }
}

func runHumanCommand(_ command: UpTilCommand) -> Int32 {
    guard let invocation = HumanInvocation(command) else { return 2 }

    do {
        let request = callRequest(tool: invocation.tool, arguments: invocation.arguments)
        let response = try MCPControlClient().send(request)
        if let error = response.error {
            writeError(error.message)
            return 1
        }
        guard
            let result = response.result,
            let rendered = MCPHumanResult.parse(result, jsonOnly: invocation.jsonOnly)
        else {
            return postSendFailure(
                "UpTil returned a malformed tool result.",
                mutates: invocation.tool != .status
            )
        }
        if rendered.isError {
            writeError(rendered.output)
            return 2
        }
        print(rendered.output)
        return 0
    } catch {
        return handleClientError(error, invocation: invocation)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = CommandLineArguments.parse(arguments) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}

let exitCode: Int32
switch command {
case .help:
    print(usage)
    exitCode = 0
case .version:
    print("uptil \(MCPControl.serverVersion)")
    exitCode = 0
case .mcp:
    exitCode = MCPStdioBridge().run()
default:
    exitCode = runHumanCommand(command)
}
exit(exitCode)
