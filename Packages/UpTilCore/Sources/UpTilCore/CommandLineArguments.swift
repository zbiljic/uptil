import Foundation

public enum UpTilCommand: Equatable, Sendable {
    case status(json: Bool)
    case start(TimeInterval)
    case indefinite
    case extend(TimeInterval)
    case shorten(TimeInterval)
    case stop
    case mcp
    case version
    case help
}

public enum CommandLineArguments {
    // swiftlint:disable:next cyclomatic_complexity
    public static func parse(_ arguments: [String]) -> UpTilCommand? {
        if arguments.count == 2, let duration = CommandLineDuration.parse(arguments[1]) {
            switch arguments[0] {
            case "start": return .start(duration)
            case "extend": return .extend(duration)
            case "shorten": return .shorten(duration)
            default: break
            }
        }
        return switch arguments {
        case ["status"]: .status(json: false)
        case ["status", "--json"]: .status(json: true)
        case ["indefinite"]: .indefinite
        case ["stop"]: .stop
        case ["mcp"]: .mcp
        case ["version"]: .version
        case ["help"], []: .help
        default: nil
        }
    }
}
