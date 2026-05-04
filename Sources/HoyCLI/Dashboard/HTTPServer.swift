import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum HTTPServerError: Error, CustomStringConvertible {
    case socketFailed(Int32)
    case bindFailed(Int32, port: Int)
    case listenFailed(Int32)

    public var description: String {
        switch self {
        case .socketFailed(let e): return "socket() failed errno=\(e)"
        case .bindFailed(let e, let p): return "bind(:\(p)) failed errno=\(e)"
        case .listenFailed(let e): return "listen() failed errno=\(e)"
        }
    }
}

public struct HTTPRequest {
    public let method: String
    public let path: String
    public let headers: [String: String]
}

public struct HTTPResponse {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public static func ok(_ body: Data, contentType: String) -> HTTPResponse {
        return HTTPResponse(
            status: 200,
            headers: ["Content-Type": contentType, "Cache-Control": "no-store"],
            body: body
        )
    }

    public static func notFound() -> HTTPResponse {
        return HTTPResponse(
            status: 404,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("not found".utf8)
        )
    }
}

/// 最小実装の HTTP/1.1 サーバ。GET 限定、Keep-Alive なし、1 接続 1 リクエスト。
/// Dashboard 用に十分な機能だけ持つ。
public final class HTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) -> HTTPResponse

    public let port: Int
    private var listenFd: Int32 = -1
    private var running = false

    public init(port: Int) {
        self.port = port
    }

    public func start(handler: @escaping Handler) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { throw HTTPServerError.socketFailed(errno) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = htonsPort(UInt16(port))
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK)  // 127.0.0.1 のみ bind

        let addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, addrLen)
            }
        }
        if bindResult < 0 {
            let e = errno
            close(fd)
            throw HTTPServerError.bindFailed(e, port: port)
        }
        if listen(fd, 16) < 0 {
            let e = errno
            close(fd)
            throw HTTPServerError.listenFailed(e)
        }

        listenFd = fd
        running = true
        let t = Thread { [weak self] in
            self?.acceptLoop(handler: handler)
        }
        t.name = "hoy-http-\(port)"
        t.start()
    }

    public func stop() {
        running = false
        if listenFd >= 0 {
            close(listenFd)
            listenFd = -1
        }
    }

    private func acceptLoop(handler: @escaping Handler) {
        while running {
            let client = accept(listenFd, nil, nil)
            if client < 0 {
                if !running { break }
                continue
            }
            let t = Thread { [weak self] in
                self?.handleClient(fd: client, handler: handler)
            }
            t.name = "hoy-http-conn-\(client)"
            t.start()
        }
    }

    private func handleClient(fd: Int32, handler: @escaping Handler) {
        defer { close(fd) }

        // リクエスト全体を 1 度に読み込む (header の終端 \r\n\r\n まで)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return }
            buffer.append(chunk, count: n)
            if let _ = buffer.range(of: Data("\r\n\r\n".utf8)) { break }
            if buffer.count > 64 * 1024 { return }  // 巨大リクエストは捨てる
        }

        guard let request = Self.parseRequest(buffer) else { return }
        let response = handler(request)
        let raw = Self.encodeResponse(response)
        raw.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            _ = Darwin.write(fd, ptr.baseAddress, raw.count)
        }
    }

    private static func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let lines = str.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colon = line.firstIndex(of: ":") {
                let k = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }
        return HTTPRequest(method: method, path: path, headers: headers)
    }

    private static func encodeResponse(_ resp: HTTPResponse) -> Data {
        let statusText = httpStatusText(resp.status)
        var head = "HTTP/1.1 \(resp.status) \(statusText)\r\n"
        var headers = resp.headers
        headers["Content-Length"] = String(resp.body.count)
        headers["Connection"] = "close"
        for (k, v) in headers {
            head += "\(k): \(v)\r\n"
        }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(resp.body)
        return out
    }

    private static func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}

// htons / htonl をプラットフォーム抽象
private func htonsPort(_ value: UInt16) -> in_port_t {
    return in_port_t(value).bigEndian
}
private func htonl(_ value: UInt32) -> UInt32 {
    return value.bigEndian
}
