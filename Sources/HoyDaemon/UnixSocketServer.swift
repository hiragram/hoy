import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public enum UnixSocketServerError: Error, CustomStringConvertible {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case pathTooLong
    case alreadyStarted

    public var description: String {
        switch self {
        case .socketFailed(let e): return "socket() failed errno=\(e)"
        case .bindFailed(let e): return "bind() failed errno=\(e)"
        case .listenFailed(let e): return "listen() failed errno=\(e)"
        case .pathTooLong: return "socket path too long"
        case .alreadyStarted: return "server already started"
        }
    }
}

/// 1リクエスト = 1コネクション の同期 Unix domain socket サーバ。
/// クライアントは JSON-RPC リクエストを 1 行 (改行終端) で送り、
/// サーバは 1 行で応答してコネクションを閉じる。MVP の最小実装。
/// ADR 0039: パーミッション 0600 で保護する。
public final class UnixSocketServer {
    public typealias Handler = @Sendable (Data) -> Data

    private let path: String
    private var listenFd: Int32 = -1
    private var thread: Thread?
    private var running = false

    public init(path: String) {
        self.path = path
    }

    public func start(handler: @escaping Handler) throws {
        guard listenFd == -1 else { throw UnixSocketServerError.alreadyStarted }

        // 既存ファイルがあれば削除 (前回起動の名残)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw UnixSocketServerError.socketFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        try withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            guard pathBytes.count < buf.count else {
                close(fd)
                throw UnixSocketServerError.pathTooLong
            }
            for (i, b) in pathBytes.enumerated() {
                buf[i] = b
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, addrLen)
            }
        }
        if bindResult < 0 {
            let e = errno
            close(fd)
            throw UnixSocketServerError.bindFailed(e)
        }
        // 0600 にする
        chmod(path, 0o600)

        if listen(fd, 16) < 0 {
            let e = errno
            close(fd)
            unlink(path)
            throw UnixSocketServerError.listenFailed(e)
        }

        listenFd = fd
        running = true
        let t = Thread { [weak self] in
            self?.acceptLoop(handler: handler)
        }
        t.name = "hoy-unix-socket"
        thread = t
        t.start()
    }

    public func stop() {
        running = false
        if listenFd >= 0 {
            close(listenFd)
            listenFd = -1
        }
        unlink(path)
    }

    private func acceptLoop(handler: @escaping Handler) {
        while running {
            let client = accept(listenFd, nil, nil)
            if client < 0 {
                if !running { break }
                continue
            }
            handleClient(fd: client, handler: handler)
        }
    }

    private func handleClient(fd: Int32, handler: @escaping Handler) {
        defer { close(fd) }
        // 改行終端で 1 メッセージ読む。MVP 簡易実装。
        var buffer = Data()
        var byte: UInt8 = 0
        while true {
            let n = read(fd, &byte, 1)
            if n <= 0 { return }
            if byte == 0x0A { break }
            buffer.append(byte)
        }
        let response = handler(buffer)
        var out = response
        out.append(0x0A)
        out.withUnsafeBytes { raw in
            _ = write(fd, raw.baseAddress, out.count)
        }
    }
}
