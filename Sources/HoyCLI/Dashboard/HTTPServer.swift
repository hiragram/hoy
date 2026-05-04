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

public enum HTTPResponse {
    case full(status: Int, headers: [String: String], body: Data)
    /// 長寿命接続。ヘッダ送出後、`onConnect` で writer を渡して任意に書き込ませる。
    /// `Content-Length` は付かない (writer が close すると connection close)。
    case streaming(headers: [String: String], onConnect: @Sendable (StreamWriter) -> Void)

    public static func ok(_ body: Data, contentType: String) -> HTTPResponse {
        return .full(
            status: 200,
            headers: ["Content-Type": contentType, "Cache-Control": "no-store"],
            body: body
        )
    }

    public static func notFound() -> HTTPResponse {
        return .full(
            status: 404,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("not found".utf8)
        )
    }
}

/// SSE などの streaming レスポンスから fd に書き出す。スレッドセーフ。
public final class StreamWriter: @unchecked Sendable {
    let fd: Int32
    private let lock = NSLock()
    private var closed = false
    private var onCloseCallbacks: [@Sendable () -> Void] = []

    init(fd: Int32) { self.fd = fd }

    public func send(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if closed { return }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            _ = Darwin.write(fd, raw.baseAddress, data.count)
        }
    }

    public func send(_ string: String) {
        send(Data(string.utf8))
    }

    public func onClose(_ callback: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        if closed {
            callback()
        } else {
            onCloseCallbacks.append(callback)
        }
    }

    func markClosed() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        let cbs = onCloseCallbacks
        onCloseCallbacks.removeAll()
        lock.unlock()
        for cb in cbs { cb() }
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
        var shouldClose = true
        defer { if shouldClose { close(fd) } }

        // リクエスト全体を 1 度に読み込む (header の終端 \r\n\r\n まで)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return }
            buffer.append(chunk, count: n)
            if let _ = buffer.range(of: Data("\r\n\r\n".utf8)) { break }
            if buffer.count > 64 * 1024 { return }
        }

        guard let request = Self.parseRequest(buffer) else { return }
        let response = handler(request)

        switch response {
        case .full(let status, let headers, let body):
            let raw = Self.encodeFullResponse(status: status, headers: headers, body: body)
            raw.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                _ = Darwin.write(fd, ptr.baseAddress, raw.count)
            }
        case .streaming(let headers, let onConnect):
            let head = Self.encodeStreamingHeaders(headers: headers)
            head.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                _ = Darwin.write(fd, ptr.baseAddress, head.count)
            }
            shouldClose = false
            // streaming: 別スレッドで writer を渡し、別スレッドで EOF 監視
            let writer = StreamWriter(fd: fd)
            let monitor = Thread { [weak self] in
                _ = self
                // クライアント切断を検出するため read で待つ
                var b: UInt8 = 0
                while read(fd, &b, 1) > 0 { /* discard */ }
                writer.markClosed()
                close(fd)
            }
            monitor.name = "hoy-http-monitor-\(fd)"
            monitor.start()
            let producer = Thread {
                onConnect(writer)
            }
            producer.name = "hoy-http-stream-\(fd)"
            producer.start()
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

    private static func encodeFullResponse(status: Int, headers: [String: String], body: Data) -> Data {
        let statusText = httpStatusText(status)
        var head = "HTTP/1.1 \(status) \(statusText)\r\n"
        var hdrs = headers
        hdrs["Content-Length"] = String(body.count)
        hdrs["Connection"] = "close"
        for (k, v) in hdrs { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    private static func encodeStreamingHeaders(headers: [String: String]) -> Data {
        var head = "HTTP/1.1 200 OK\r\n"
        var hdrs = headers
        hdrs["Connection"] = "keep-alive"
        for (k, v) in hdrs { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8)
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
