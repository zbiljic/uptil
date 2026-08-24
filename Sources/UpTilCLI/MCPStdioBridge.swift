import Foundation
import UpTilCore

struct MCPStdioBridge {
    private let client = MCPControlClient()

    func run() -> Int32 {
        while let input = readInputLine() {
            guard let object = try? MCPFraming.objectData(from: input) else {
                let code = isBatch(input) ? -32600 : -32700
                writeError(id: nil, code: code, message: "Invalid JSON-RPC input.")
                continue
            }
            do {
                let response = try client.sendRaw(object)
                if let framed = try? MCPFraming.line(for: response) {
                    FileHandle.standardOutput.write(framed)
                }
            } catch {
                let request = try? MCPControl.decoder().decode(MCPRequest.self, from: object)
                if let request, !request.isNotification {
                    writeError(id: request.id, code: -32603, message: "UpTil app is unavailable.")
                }
                FileHandle.standardError.write(Data("uptil mcp: \(error)\n".utf8))
            }
        }
        return 0
    }

    private func writeError(id: JSONValue?, code: Int, message: String) {
        guard
            let data = try? MCPControl.encoder().encode(MCPResponse(
                id: id,
                error: MCPError(code: code, message: message)
            )), let line = try? MCPFraming.line(for: data) else { return }
        FileHandle.standardOutput.write(line)
    }

    private func isBatch(_ line: Data) -> Bool {
        guard line.last == 0x0A else { return false }
        return (try? JSONSerialization.jsonObject(with: line.dropLast())) is [Any]
    }

    private func readInputLine() -> Data? {
        var line = Data()
        while line.count <= MCPFraming.maximumLineBytes {
            let byte = FileHandle.standardInput.readData(ofLength: 1)
            guard !byte.isEmpty else { return line.isEmpty ? nil : line }
            line.append(byte)
            if byte.first == 0x0A {
                return line
            }
        }
        return nil
    }
}
