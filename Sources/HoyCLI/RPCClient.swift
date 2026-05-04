import Foundation
import HoyProtocol
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum RPCClientError: Error, CustomStringConvertible {
    case connectFailed(Int32)
    case writeFailed
    case readFailed
    case decodeFailed(String)
    case rpcError(RPCError)

    public var description: String {
        switch self {
        case .connectFailed(let e): return "connect() failed errno=\(e). daemon が起動しているか確認してください"
        case .writeFailed: return "ソケット書き込みに失敗"
        case .readFailed: return "ソケット読み取りに失敗"
        case .decodeFailed(let d): return "レスポンスのデコード失敗: \(d)"
        case .rpcError(let err): return "RPC error \(err.code): \(err.message)"
        }
    }
}

public struct RPCClient {
    public let socketPath: String
    public let token: String?

    public init(socketPath: String, token: String? = nil) {
        self.socketPath = socketPath
        self.token = token
    }

    public func call<M: RPCMethod>(
        _ method: M.Type,
        params: M.Params,
        requestId: String = UUID().uuidString
    ) throws -> M.Result {
        let auth = token.map { AuthInfo(token: $0) }
        let req = RPCRequest(id: requestId, method: M.name, params: params, auth: auth)
        let reqData = try JSONEncoder().encode(req)

        let respData = try sendOnce(reqData)
        let resp = try JSONDecoder().decode(RPCResponse<M.Result>.self, from: respData)
        if let error = resp.error { throw RPCClientError.rpcError(error) }
        guard let result = resp.result else {
            throw RPCClientError.decodeFailed("missing result")
        }
        return result
    }

    /// 任意の JSON-RPC ペイロードを 1 リクエストとして送信し、レスポンス Data を返す。
    /// MCP 等、汎用転送に使う。
    public func rawSend(_ payload: Data) throws -> Data {
        return try sendOnce(payload)
    }

    private func sendOnce(_ payload: Data) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw RPCClientError.connectFailed(errno) }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() where i < buf.count {
                buf[i] = b
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, addrLen)
            }
        }
        if rc != 0 { throw RPCClientError.connectFailed(errno) }

        var data = payload
        data.append(0x0A)
        let written = data.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, data.count)
        }
        if written != data.count { throw RPCClientError.writeFailed }

        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
            if out.last == 0x0A {
                out.removeLast()
                break
            }
        }
        return out
    }
}
