import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Self])
    case object([String: Self])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: Self].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var objectValue: [String: Self]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
}

public enum MCPControl {
    public static let protocolVersion = "2026-07-28"
    public static let serverName = "uptil"
    public static let serverVersion = "0.1.0"
    public static let statusSchemaVersion = 1

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func rfc3339String(_ date: Date) -> String? {
        guard
            let data = try? encoder().encode(date),
            let value = try? JSONDecoder().decode(String.self, from: data),
            value.utf8.count == 20
        else { return nil }
        let bytes = Array(value.utf8)
        let digitIndices = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        guard
            digitIndices.allSatisfy({ (0x30 ... 0x39).contains(bytes[$0]) }),
            bytes[4] == 0x2D, bytes[7] == 0x2D, bytes[10] == 0x54,
            bytes[13] == 0x3A, bytes[16] == 0x3A, bytes[19] == 0x5A
        else { return nil }
        return value
    }
}

/// A JSON-RPC request ID. Integers decode straight into `Int64`, never through `Double`,
/// so every accepted ID echoes back exactly; fractional and out-of-range numbers are rejected.
public enum MCPRequestID: Codable, Hashable, Sendable {
    case string(String)
    case number(Int64)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .number(value)
        } else {
            self = try .string(container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        }
    }
}

public struct MCPRequest: Codable, Equatable, Sendable {
    public let jsonrpc: String
    public let id: MCPRequestID?
    public let hasID: Bool
    public let method: String
    public let params: JSONValue?

    public init(id: MCPRequestID?, method: String, params: JSONValue? = nil) {
        jsonrpc = "2.0"
        self.id = id
        hasID = id != nil
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        hasID = container.contains(.id)
        // A present but null or malformed ID stays invalid rather than turning the request into a notification.
        id = try? container.decodeIfPresent(MCPRequestID.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        if hasID {
            try container.encode(id, forKey: .id)
        }
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }

    public var isNotification: Bool {
        !hasID
    }

    public var hasValidID: Bool {
        !hasID || id != nil
    }
}

public struct MCPError: Codable, Equatable, Sendable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct MCPResponse: Codable, Equatable, Sendable {
    public let jsonrpc: String
    public let id: MCPRequestID?
    public let result: JSONValue?
    public let error: MCPError?

    public init(id: MCPRequestID?, result: JSONValue) {
        jsonrpc = "2.0"
        self.id = id
        self.result = result
        error = nil
    }

    public init(id: MCPRequestID?, error: MCPError) {
        jsonrpc = "2.0"
        self.id = id
        result = nil
        self.error = error
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, id, result, error }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        id = try container.decodeIfPresent(MCPRequestID.self, forKey: .id)
        let hasResult = container.contains(.result)
        let hasError = container.contains(.error)
        guard hasResult != hasError else {
            throw DecodingError.dataCorruptedError(
                forKey: .result,
                in: container,
                debugDescription: "Response must contain exactly one result or error."
            )
        }
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        error = try container.decodeIfPresent(MCPError.self, forKey: .error)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        if let result {
            try container.encode(result, forKey: .result)
        }
        if let error {
            try container.encode(error, forKey: .error)
        }
    }

    public var isValid: Bool {
        jsonrpc == "2.0" && (result != nil) != (error != nil)
    }
}

public enum MCPTool: String, CaseIterable, Sendable {
    case status = "uptil.status"
    case start = "uptil.start"
    case indefinite = "uptil.indefinite"
    case extend = "uptil.extend"
    case shorten = "uptil.shorten"
    case stop = "uptil.stop"

    public var schema: JSONValue {
        let schemaVersion = JSONValue.string("https://json-schema.org/draft/2020-12/schema")
        let empty: JSONValue = .object([
            "$schema": schemaVersion,
            "type": .string("object"),
            "additionalProperties": .bool(false),
        ])
        let duration: JSONValue = .object([
            "$schema": schemaVersion,
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("durationSeconds")]),
            "properties": .object([
                "durationSeconds": .object(["type": .string("number"), "exclusiveMinimum": .number(0)]),
            ]),
        ])
        return switch self {
        case .status, .indefinite, .stop: empty
        case .start, .extend, .shorten: duration
        }
    }

    public static var statusOutputSchema: JSONValue {
        func branch(state: String, assertionActive: Bool, allowsUntil: Bool) -> JSONValue {
            var properties: [String: JSONValue] = [
                "schemaVersion": .object(["const": .number(Double(MCPControl.statusSchemaVersion))]),
                "state": .object(["const": .string(state)]),
                "assertionActive": .object(["const": .bool(assertionActive)]),
                "pid": .object(["type": .string("integer"), "minimum": .number(1)]),
            ]
            var required: [JSONValue] = [
                .string("schemaVersion"), .string("state"), .string("assertionActive"), .string("pid"),
            ]
            if allowsUntil {
                properties["until"] = .object(["type": .string("string"), "format": .string("date-time")])
                required.append(.string("until"))
            }
            return .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(required),
                "properties": .object(properties),
            ])
        }
        return .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "oneOf": .array([
                branch(state: "idle", assertionActive: false, allowsUntil: false),
                branch(state: "timed", assertionActive: true, allowsUntil: true),
                branch(state: "indefinite", assertionActive: true, allowsUntil: false),
            ]),
        ])
    }

    public var description: String {
        switch self {
        case .status: "Return UpTil's authoritative session status."
        case .start: "Start or replace a timed keep-awake session."
        case .indefinite: "Start or replace an indefinite keep-awake session."
        case .extend: "Extend the active timed session."
        case .shorten: "Shorten the active timed session without reaching now."
        case .stop: "Stop the current keep-awake session."
        }
    }
}

public enum UpTilLiveStatus: Codable, Equatable, Sendable {
    case idle(pid: Int32)
    case timed(until: Date, pid: Int32)
    case indefinite(pid: Int32)

    enum CodingKeys: String, CodingKey { case schemaVersion, state, until, assertionActive, pid }
    enum State: String, Codable { case idle, timed, indefinite }

    public var text: String {
        switch self {
        case .idle: "Idle."
        case let .timed(until, _): "Keeping awake until \(MCPControl.rfc3339String(until) ?? "")."
        case .indefinite: "Keeping awake indefinitely."
        }
    }

    public var until: Date? {
        if case let .timed(until, _) = self {
            return until
        }
        return nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MCPControl.statusSchemaVersion, forKey: .schemaVersion)
        switch self {
        case let .idle(pid):
            try container.encode(State.idle, forKey: .state)
            try container.encode(false, forKey: .assertionActive)
            try container.encode(pid, forKey: .pid)
        case let .timed(until, pid):
            try container.encode(State.timed, forKey: .state)
            guard let renderedUntil = MCPControl.rfc3339String(until) else {
                throw EncodingError.invalidValue(
                    until,
                    .init(codingPath: container.codingPath, debugDescription: "Invalid timed status.")
                )
            }
            try container.encode(renderedUntil, forKey: .until)
            try container.encode(true, forKey: .assertionActive)
            try container.encode(pid, forKey: .pid)
        case let .indefinite(pid):
            try container.encode(State.indefinite, forKey: .state)
            try container.encode(true, forKey: .assertionActive)
            try container.encode(pid, forKey: .pid)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
        let keys = Set(allKeys.allKeys.map(\.stringValue))
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        let state = try container.decode(State.self, forKey: .state)
        let active = try container.decode(Bool.self, forKey: .assertionActive)
        let pid = try container.decode(Int32.self, forKey: .pid)
        guard version == MCPControl.statusSchemaVersion, pid > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Invalid live status."
            )
        }
        switch state {
        case .idle:
            guard !active, keys == ["schemaVersion", "state", "assertionActive", "pid"] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .state,
                    in: container,
                    debugDescription: "Invalid idle status."
                )
            }
            self = .idle(pid: pid)
        case .timed:
            guard active, keys == ["schemaVersion", "state", "until", "assertionActive", "pid"] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .state,
                    in: container,
                    debugDescription: "Invalid timed status."
                )
            }
            self = try .timed(until: container.decode(Date.self, forKey: .until), pid: pid)
        case .indefinite:
            guard active, keys == ["schemaVersion", "state", "assertionActive", "pid"] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .state,
                    in: container,
                    debugDescription: "Invalid indefinite status."
                )
            }
            self = .indefinite(pid: pid)
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) {
        self.stringValue = stringValue; intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue); self.intValue = intValue
    }
}

public struct UpTilUnavailableStatus: Encodable, Equatable, Sendable {
    public let schemaVersion = MCPControl.statusSchemaVersion
    public let state = "unavailable"
    public init() {}
}

public struct MCPHumanResult: Equatable, Sendable {
    public let output: String
    public let isError: Bool

    public static func parse(_ value: JSONValue, jsonOnly: Bool) -> Self? {
        guard
            let result = value.objectValue,
            case let .bool(isError)? = result["isError"]
        else { return nil }
        if jsonOnly {
            guard
                case .object? = result["structuredContent"],
                let data = try? MCPControl.encoder().encode(result["structuredContent"]),
                (try? MCPControl.decoder().decode(UpTilLiveStatus.self, from: data)) != nil,
                let output = String(data: data, encoding: .utf8)
            else { return nil }
            return Self(output: output, isError: isError)
        }
        guard
            case let .array(content)? = result["content"],
            case let .object(first)? = content.first,
            first["type"] == .string("text"),
            case let .string(output)? = first["text"]
        else { return nil }
        return Self(output: output, isError: isError)
    }
}
