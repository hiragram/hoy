import Foundation
import HoyProtocol

/// MCP stdio サーバ。
/// MVP ではプロトコルの最小限 (initialize / tools/list / tools/call) を実装。
/// tools/call はクライアント (上位レイヤ) が処理する。テスト容易性のため依存注入。
public final class MCPServer {
    public typealias ToolCall = (_ name: String, _ argumentsJSON: Data) -> Data

    private let toolCall: ToolCall
    private let tools: [Tool]
    private let serverName: String
    private let serverVersion: String

    public init(
        tools: [Tool],
        toolCall: @escaping ToolCall,
        serverName: String = "hoy",
        serverVersion: String = HoyProtocolVersion.current
    ) {
        self.tools = tools
        self.toolCall = toolCall
        self.serverName = serverName
        self.serverVersion = serverVersion
    }

    /// stdin/stdout を使って実行する。1リクエスト = 1行 (改行終端 JSON)。
    public func run(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) {
        let stream = LineReader(handle: input)
        while let line = stream.readLine() {
            guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
            let response = process(requestData: data)
            if !response.isEmpty {
                output.write(response)
                output.write(Data("\n".utf8))
            }
        }
    }

    /// 単発のリクエスト処理 (テスト容易性のため公開)。
    public func process(requestData: Data) -> Data {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        struct Header: Decodable { let id: JSONId?; let method: String }
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: requestData)
        } catch {
            return encodeParseError(encoder: encoder)
        }

        // notification (id なし) は応答しない
        guard let id = header.id else { return Data() }

        do {
            switch header.method {
            case "initialize":
                let result = InitializeResult(
                    protocolVersion: "2024-11-05",
                    capabilities: Capabilities(tools: ToolsCapability(listChanged: false)),
                    serverInfo: ServerInfo(name: serverName, version: serverVersion)
                )
                return try encode(id: id, result: result, encoder: encoder)

            case "notifications/initialized":
                return Data()

            case "tools/list":
                let result = ToolsListResult(tools: tools)
                return try encode(id: id, result: result, encoder: encoder)

            case "tools/call":
                struct Wrap: Decodable {
                    struct Params: Decodable {
                        let name: String
                        let arguments: JSONValue?
                    }
                    let params: Params
                }
                let parsed = try decoder.decode(Wrap.self, from: requestData)
                let argsData: Data
                if let args = parsed.params.arguments {
                    argsData = try encoder.encode(args)
                } else {
                    argsData = Data("{}".utf8)
                }
                let resultData = toolCall(parsed.params.name, argsData)
                let result = ToolCallResult(
                    content: [ContentItem(
                        type: "text",
                        text: String(data: resultData, encoding: .utf8) ?? ""
                    )],
                    isError: false
                )
                return try encode(id: id, result: result, encoder: encoder)

            default:
                return encodeError(
                    id: id, code: -32601, message: "method not found: \(header.method)",
                    encoder: encoder
                )
            }
        } catch {
            return encodeError(
                id: id, code: -32603, message: String(describing: error),
                encoder: encoder
            )
        }
    }

    private func encode<R: Encodable>(
        id: JSONId, result: R, encoder: JSONEncoder
    ) throws -> Data {
        return try encoder.encode(Resp<R>(id: id, result: result))
    }

    private func encodeError(
        id: JSONId, code: Int, message: String, encoder: JSONEncoder
    ) -> Data {
        struct Err: Encodable {
            let jsonrpc = "2.0"
            let id: JSONId
            let error: ErrorBody
        }
        struct ErrorBody: Encodable { let code: Int; let message: String }
        return (try? encoder.encode(Err(id: id, error: ErrorBody(code: code, message: message)))) ?? Data()
    }

    private func encodeParseError(encoder: JSONEncoder) -> Data {
        struct Err: Encodable {
            let jsonrpc = "2.0"
            let id: JSONId? = nil
            let error: ErrorBody
        }
        struct ErrorBody: Encodable { let code: Int = -32700; let message: String = "parse error" }
        return (try? encoder.encode(Err(error: ErrorBody()))) ?? Data()
    }
}

private struct Resp<R: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: JSONId
    let result: R
}

// MARK: - DTO

public struct Tool: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

struct InitializeResult: Encodable {
    let protocolVersion: String
    let capabilities: Capabilities
    let serverInfo: ServerInfo
}

struct Capabilities: Encodable { let tools: ToolsCapability }
struct ToolsCapability: Encodable { let listChanged: Bool }
struct ServerInfo: Encodable { let name: String; let version: String }

struct ToolsListResult: Encodable { let tools: [Tool] }

struct ToolCallResult: Encodable {
    let content: [ContentItem]
    let isError: Bool
}

struct ContentItem: Encodable { let type: String; let text: String }

// MARK: - JSON helpers

public enum JSONId: Codable, Sendable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s); return }
        let i = try c.decode(Int.self)
        self = .int(i)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        }
    }
}

public enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "unsupported json value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Stdin line reader

final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readLine() -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: nl)
                buffer = buffer.suffix(from: buffer.index(after: nl))
                return String(data: line, encoding: .utf8) ?? ""
            }
            let chunk = handle.availableData
            if chunk.isEmpty {
                if buffer.isEmpty { return nil }
                let remaining = String(data: buffer, encoding: .utf8)
                buffer.removeAll()
                return remaining
            }
            buffer.append(chunk)
        }
    }
}
