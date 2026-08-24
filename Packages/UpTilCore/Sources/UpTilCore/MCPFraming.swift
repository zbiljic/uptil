import Foundation

public enum MCPFramingError: Error, Equatable, Sendable {
    case empty
    case tooLarge
    case containsCarriageReturn
    case containsNewline
    case invalidUTF8
    case notObject
    case missingLineFeed
}

public enum MCPFraming {
    public static let maximumLineBytes = 64 * 1024

    public static func line(for data: Data) throws -> Data {
        guard !data.isEmpty else { throw MCPFramingError.empty }
        guard data.count <= maximumLineBytes else { throw MCPFramingError.tooLarge }
        guard !data.contains(0x0D) else { throw MCPFramingError.containsCarriageReturn }
        guard !data.contains(0x0A) else { throw MCPFramingError.containsNewline }
        guard String(data: data, encoding: .utf8) != nil else { throw MCPFramingError.invalidUTF8 }
        var result = data
        result.append(0x0A)
        return result
    }

    public static func objectData(from line: Data) throws -> Data {
        guard line.last == 0x0A else { throw MCPFramingError.missingLineFeed }
        let payload = line.dropLast()
        guard !payload.isEmpty else { throw MCPFramingError.empty }
        guard payload.count <= maximumLineBytes else { throw MCPFramingError.tooLarge }
        guard !payload.contains(0x0D) else { throw MCPFramingError.containsCarriageReturn }
        guard !payload.contains(0x0A) else { throw MCPFramingError.containsNewline }
        guard String(data: payload, encoding: .utf8) != nil else { throw MCPFramingError.invalidUTF8 }
        let object = try JSONSerialization.jsonObject(with: Data(payload))
        guard object is [String: Any] else { throw MCPFramingError.notObject }
        return Data(payload)
    }
}
