import Foundation
import Testing
@testable import UpTilCore

@Suite("MCP control contract")
struct MCPControlTests {
    @Test("request IDs preserve requests and notifications")
    func requestIDs() throws {
        let request = MCPRequest(id: .string("id-1"), method: "tools/list")
        let decoded = try MCPControl.decoder().decode(MCPRequest.self, from: MCPControl.encoder().encode(request))
        #expect(decoded.id == .string("id-1"))
        #expect(decoded.hasID)
        #expect(!decoded.isNotification)

        let notification = try MCPControl.decoder().decode(
            MCPRequest.self,
            from: Data("{\"jsonrpc\":\"2.0\",\"method\":\"tools/list\"}".utf8)
        )
        #expect(notification.id == nil)
        #expect(!notification.hasID)
        #expect(notification.isNotification)

        let numeric = MCPRequest(id: .number(7), method: "tools/list")
        let numericRoundTrip = try MCPControl.decoder().decode(
            MCPRequest.self,
            from: MCPControl.encoder().encode(numeric)
        )
        #expect(numericRoundTrip.id == .number(7))
        #expect(numericRoundTrip.hasValidID)
        #expect(request.hasValidID)
        for rawID in ["null", "true", "[]", "{}", "1.5", "9223372036854775808", "-9223372036854775809"] {
            let invalid = try MCPControl.decoder().decode(
                MCPRequest.self,
                from: Data("{\"jsonrpc\":\"2.0\",\"id\":\(rawID),\"method\":\"tools/list\"}".utf8)
            )
            #expect(invalid.hasID)
            #expect(!invalid.isNotification)
            #expect(!invalid.hasValidID)
        }
    }

    @Test("integer IDs beyond Double precision echo exactly")
    func exactIntegerIDs() throws {
        let cases: [(raw: String, id: MCPRequestID)] = [
            ("9007199254740993", .number(9_007_199_254_740_993)),
            ("9223372036854775807", .number(Int64.max)),
            ("-9223372036854775808", .number(Int64.min)),
            ("\"id-2\"", .string("id-2")),
        ]
        for (raw, id) in cases {
            let request = try MCPControl.decoder().decode(
                MCPRequest.self,
                from: Data("{\"jsonrpc\":\"2.0\",\"id\":\(raw),\"method\":\"tools/list\"}".utf8)
            )
            #expect(request.id == id)
            #expect(request.hasValidID)
            for response in [
                MCPResponse(id: request.id, result: .object([:])),
                MCPResponse(id: request.id, error: MCPError(code: -32601, message: "Method not found")),
            ] {
                let encoded = try MCPControl.encoder().encode(response)
                let text = try #require(String(bytes: encoded, encoding: .utf8))
                #expect(text.contains("\"id\":\(raw),"))
                #expect(try MCPControl.decoder().decode(MCPResponse.self, from: encoded).id == id)
            }
        }
    }

    @Test("response requires exactly one result or error")
    func responseExclusivity() throws {
        let success = MCPResponse(id: .number(1), result: .object([:]))
        #expect(try MCPControl.decoder().decode(MCPResponse.self, from: MCPControl.encoder().encode(success)).isValid)
        let nullIDError = try MCPControl.encoder().encode(MCPResponse(
            id: nil,
            error: MCPError(code: -32700, message: "Parse error")
        ))
        let nullIDObject = try #require(JSONSerialization.jsonObject(with: nullIDError) as? [String: Any])
        #expect(nullIDObject["id"] is NSNull)
        #expect(throws: Error.self) {
            try MCPControl.decoder().decode(
                MCPResponse.self,
                from: Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{},\"error\":{\"code\":1,\"message\":\"bad\"}}"
                    .utf8)
            )
        }
        #expect(throws: Error.self) {
            try MCPControl.decoder().decode(MCPResponse.self, from: Data("{\"jsonrpc\":\"2.0\",\"id\":1}".utf8))
        }
        for rawID in ["true", "1.5", "[]", "{}"] {
            #expect(throws: Error.self) {
                try MCPControl.decoder().decode(
                    MCPResponse.self,
                    from: Data("{\"jsonrpc\":\"2.0\",\"id\":\(rawID),\"result\":{}}".utf8)
                )
            }
        }
    }

    @Test("tool catalog order schemas and annotations are stable")
    func catalog() {
        #expect(MCPTool.allCases.map(\.rawValue) == [
            "uptil.status", "uptil.start", "uptil.indefinite", "uptil.extend", "uptil.shorten", "uptil.stop",
        ])
        #expect(MCPTool.status.schema.objectValue?["additionalProperties"] == .bool(false))
        #expect(MCPTool.start.schema.objectValue?["required"] == .array([.string("durationSeconds")]))
        let durationProperty = MCPTool.start.schema.objectValue?["properties"]?.objectValue?["durationSeconds"]
        #expect(durationProperty?.objectValue?["exclusiveMinimum"] == .number(0))
        let schema = MCPTool.statusOutputSchema.objectValue?["$schema"]
        #expect(schema == .string("https://json-schema.org/draft/2020-12/schema"))
        guard case let .array(branches)? = MCPTool.statusOutputSchema.objectValue?["oneOf"] else {
            Issue.record("missing status oneOf branches")
            return
        }
        let expectedBranches: [(Set<String>, Set<String>)] = [
            (
                ["schemaVersion", "state", "assertionActive", "pid"],
                ["schemaVersion", "state", "assertionActive", "pid"]
            ),
            (
                ["schemaVersion", "state", "until", "assertionActive", "pid"],
                ["schemaVersion", "state", "until", "assertionActive", "pid"]
            ),
            (
                ["schemaVersion", "state", "assertionActive", "pid"],
                ["schemaVersion", "state", "assertionActive", "pid"]
            ),
            (
                ["schemaVersion", "state", "assertionActive", "remainingSeconds", "pid"],
                ["schemaVersion", "state", "assertionActive", "remainingSeconds", "pid"]
            ),
        ]
        #expect(branches.count == expectedBranches.count)
        for (branch, expected) in zip(branches, expectedBranches) {
            let object = branch.objectValue
            let requiredValues: [JSONValue]? = if case let .array(values)? = object?["required"] {
                values
            } else {
                nil
            }
            let required = requiredValues?.compactMap { value -> String? in
                if case let .string(key) = value {
                    return key
                }
                return nil
            }
            #expect(Set(required ?? []) == expected.0)
            let propertyKeys = object?["properties"]?.objectValue.map { Array($0.keys) } ?? []
            #expect(Set(propertyKeys) == expected.1)
            #expect(object?["additionalProperties"] == .bool(false))
        }
        #expect(MCPTool.statusOutputSchema.objectValue?["additionalProperties"] == nil)
    }

    @Test("status uses exact discriminated flat JSON")
    func statusEncoding() throws {
        let idle = UpTilLiveStatus.idle(pid: 42)
        let text = try #require(String(bytes: MCPControl.encoder().encode(idle), encoding: .utf8))
        #expect(text == "{\"assertionActive\":false,\"pid\":42,\"schemaVersion\":1,\"state\":\"idle\"}")

        let deadline = Date(timeIntervalSince1970: 1_787_437_800)
        let timed = UpTilLiveStatus.timed(until: deadline, pid: 42)
        let timedText = try #require(String(bytes: MCPControl.encoder().encode(timed), encoding: .utf8))
        #expect(timedText == "{\"assertionActive\":true,\"pid\":42,\"schemaVersion\":1," +
            "\"state\":\"timed\",\"until\":\"2026-08-22T22:30:00Z\"}")
        let indefiniteText = try #require(String(
            bytes: MCPControl.encoder().encode(UpTilLiveStatus.indefinite(pid: 42)),
            encoding: .utf8
        ))
        #expect(indefiniteText == "{\"assertionActive\":true,\"pid\":42,\"schemaVersion\":1,\"state\":\"indefinite\"}")
        #expect(try String(bytes: MCPControl.encoder().encode(UpTilUnavailableStatus()), encoding: .utf8) ==
            "{\"schemaVersion\":1,\"state\":\"unavailable\"}")
        for invalid in [
            "{\"schemaVersion\":2,\"state\":\"idle\",\"assertionActive\":false,\"pid\":42}",
            "{\"schemaVersion\":1,\"state\":\"idle\",\"assertionActive\":false," +
                "\"pid\":42,\"until\":\"2026-08-22T22:30:00Z\"}",
            "{\"schemaVersion\":1,\"state\":\"idle\",\"assertionActive\":false,\"pid\":42,\"extra\":true}",
            "{\"schemaVersion\":1,\"state\":\"timed\",\"assertionActive\":true,\"pid\":42}",
        ] {
            #expect(throws: Error.self) {
                try MCPControl.decoder().decode(UpTilLiveStatus.self, from: Data(invalid.utf8))
            }
        }
        let hugeDate = Date(timeIntervalSinceReferenceDate: 1000).addingTimeInterval(Double.greatestFiniteMagnitude)
        #expect(MCPControl.rfc3339String(hugeDate) == nil)
    }

    @Test("duration grammar accepts only positive simple units")
    func durationGrammar() {
        #expect(CommandLineDuration.parse("30s") == 30)
        #expect(CommandLineDuration.parse("15m") == 900)
        #expect(CommandLineDuration.parse("1.5h") == 5400)
        for invalid in [
            "",
            "30",
            "1h30m",
            "+1m",
            "-1m",
            "0s",
            " 1m",
            "1 m",
            "nanm",
            "infinityh",
            "1H",
            "1e309h",
            "1m extra",
        ] {
            #expect(CommandLineDuration.parse(invalid) == nil)
        }
    }

    @Test("CLI arity is exact")
    func commandArity() {
        #expect(CommandLineArguments.parse([]) == .help)
        #expect(CommandLineArguments.parse(["mcp"]) == .mcp)
        #expect(CommandLineArguments.parse(["mcp", "x"]) == nil)
        #expect(CommandLineArguments.parse(["status", "--json"]) == .status(json: true))
        #expect(CommandLineArguments.parse(["status", "x"]) == nil)
        #expect(CommandLineArguments.parse(["start", "1m"]) == .start(60))
        #expect(CommandLineArguments.parse(["start"]) == nil)
        #expect(CommandLineArguments.parse(["stop", "now"]) == nil)
        #expect(CommandLineArguments.parse(["status"]) == .status(json: false))
        #expect(CommandLineArguments.parse(["indefinite"]) == .indefinite)
        #expect(CommandLineArguments.parse(["extend", "1s"]) == .extend(1))
        #expect(CommandLineArguments.parse(["shorten", "1h"]) == .shorten(3600))
        #expect(CommandLineArguments.parse(["stop"]) == .stop)
        #expect(CommandLineArguments.parse(["version"]) == .version)
        #expect(CommandLineArguments.parse(["help"]) == .help)
        #expect(CommandLineArguments.parse(["version", "extra"]) == nil)
    }

    @Test("human result rendering rejects malformed success shapes")
    func humanResultRendering() {
        let structured: JSONValue = .object([
            "schemaVersion": .number(1), "state": .string("idle"), "assertionActive": .bool(false), "pid": .number(42),
        ])
        let valid: JSONValue = .object([
            "content": .array([.object(["type": .string("text"), "text": .string("Idle")])]),
            "structuredContent": structured,
            "isError": .bool(false),
        ])
        #expect(MCPHumanResult.parse(valid, jsonOnly: false) == MCPHumanResult(output: "Idle", isError: false))
        #expect(MCPHumanResult.parse(valid, jsonOnly: true)?.isError == false)
        #expect(MCPHumanResult.parse(.object(["isError": .bool(false)]), jsonOnly: false) == nil)
        #expect(MCPHumanResult.parse(.object([
            "content": .array([]), "isError": .bool(false),
        ]), jsonOnly: false) == nil)
        #expect(MCPHumanResult.parse(.object([
            "structuredContent": .string("wrong"), "isError": .bool(false),
        ]), jsonOnly: true) == nil)
        #expect(MCPHumanResult.parse(.object([
            "content": .array([.object(["type": .string("text"), "text": .string("Idle")])]),
        ]), jsonOnly: false) == nil)
        #expect(MCPHumanResult.parse(.object([
            "structuredContent": .object(["schemaVersion": .number(2)]), "isError": .bool(false),
        ]), jsonOnly: true) == nil)
    }
}

extension MCPControlTests {
    @Test("paused status uses exact flat JSON and round-trips")
    func pausedStatusEncoding() throws {
        let paused = UpTilLiveStatus.paused(remaining: 720, pid: 42)
        let encoded = try MCPControl.encoder().encode(paused)
        #expect(try String(bytes: encoded, encoding: .utf8) ==
            "{\"assertionActive\":false,\"pid\":42,\"remainingSeconds\":720,\"schemaVersion\":1,\"state\":\"paused\"}")
        #expect(try MCPControl.decoder().decode(UpTilLiveStatus.self, from: encoded) == paused)
        let fractional = UpTilLiveStatus.paused(remaining: 719.5, pid: 42)
        #expect(try MCPControl.decoder().decode(
            UpTilLiveStatus.self,
            from: MCPControl.encoder().encode(fractional)
        ) == fractional)
        #expect(paused.text == "Paused with 12m remaining.")
        #expect(paused.until == nil)
        for invalid in [0, -1, TimeInterval.nan, .infinity] {
            #expect(throws: Error.self) {
                try MCPControl.encoder().encode(UpTilLiveStatus.paused(remaining: invalid, pid: 42))
            }
        }
    }

    @Test("paused status rejects malformed payloads")
    func pausedStatusRejectsMalformedPayloads() {
        let valid = "\"schemaVersion\":1,\"state\":\"paused\",\"pid\":42"
        for invalid in [
            "{\(valid),\"assertionActive\":false}",
            "{\(valid),\"assertionActive\":false,\"remainingSeconds\":720,\"extra\":true}",
            "{\(valid),\"assertionActive\":true,\"remainingSeconds\":720}",
            "{\(valid),\"assertionActive\":false,\"remainingSeconds\":720,\"until\":\"2026-08-22T22:30:00Z\"}",
            "{\(valid),\"assertionActive\":false,\"remainingSeconds\":0}",
            "{\(valid),\"assertionActive\":false,\"remainingSeconds\":-1}",
            "{\(valid),\"assertionActive\":false,\"remainingSeconds\":\"720\"}",
            "{\(valid),\"assertionActive\":false,\"remainingSeconds\":true}",
        ] {
            #expect(throws: Error.self) {
                try MCPControl.decoder().decode(UpTilLiveStatus.self, from: Data(invalid.utf8))
            }
        }
    }

    @Test("paused status matches its schema branch and parses for the CLI")
    func pausedStatusSchemaAndHumanResult() throws {
        guard case let .array(branches)? = MCPTool.statusOutputSchema.objectValue?["oneOf"] else {
            Issue.record("missing status oneOf branches")
            return
        }
        let properties = try #require(branches.last?.objectValue?["properties"]?.objectValue)
        #expect(properties["state"] == .object(["const": .string("paused")]))
        #expect(properties["assertionActive"] == .object(["const": .bool(false)]))
        #expect(properties["remainingSeconds"] == .object([
            "type": .string("number"), "exclusiveMinimum": .number(0),
        ]))

        let structured = try MCPControl.decoder().decode(
            JSONValue.self,
            from: MCPControl.encoder().encode(UpTilLiveStatus.paused(remaining: 720, pid: 42))
        )
        let result: JSONValue = .object([
            "content": .array([.object(["type": .string("text"), "text": .string("Paused with 12m remaining.")])]),
            "structuredContent": structured,
            "isError": .bool(false),
        ])
        #expect(MCPHumanResult.parse(result, jsonOnly: false)?.output == "Paused with 12m remaining.")
        let json = try #require(MCPHumanResult.parse(result, jsonOnly: true)?.output)
        #expect(json.contains("\"state\":\"paused\""))
    }
}
