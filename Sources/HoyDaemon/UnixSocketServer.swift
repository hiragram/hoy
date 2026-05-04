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

/// 永続接続対応の Unix domain socket サーバ。
/// クライアントは改行終端の JSON-RPC リクエストを連続して送れる。
/// 各リクエストには ConnectionContext が渡され、サーバから client への
/// 非同期 push (events 等) も同じ socket に書き出せる。
/// ADR 0039: パーミッション 0600 で保護する。
public final class UnixSocketServer {
    public typealias Handler = @Sendable (Data, ConnectionContext) -> Data

    /// 1 接続を表す。複数スレッドから write される可能性があるので lock で同期。
    public final class ConnectionContext: @unchecked Sendable {
        let fd: Int32
        private let writeLock = NSLock()
        private var cleanups: [() -> Void] = []
        private let cleanupLock = NSLock()
        private var closed = false

        init(fd: Int32) { self.fd = fd }

        public func write(_ data: Data) {
            writeLock.lock(); defer { writeLock.unlock() }
            if closed { return }
            var d = data
            if d.last != 0x0A { d.append(0x0A) }
            d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                _ = Darwin.write(fd, raw.baseAddress, d.count)
            }
        }

        public func addCleanup(_ f: @escaping () -> Void) {
            cleanupLock.lock(); defer { cleanupLock.unlock() }
            cleanups.append(f)
        }

        func performCleanup() {
            cleanupLock.lock()
            let toRun = cleanups
            cleanups.removeAll()
            cleanupLock.unlock()
            for f in toRun { f() }
            writeLock.lock(); closed = true; writeLock.unlock()
        }
    }

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
            // クライアントごとに別スレッドで処理する。
            // events.subscribe のような長寿命接続で他クライアントを
            // ブロックしないようにする。
            let t = Thread { [weak self] in
                self?.handleClient(fd: client, handler: handler)
            }
            t.name = "hoy-conn-\(client)"
            t.start()
        }
    }

    private func handleClient(fd: Int32, handler: @escaping Handler) {
        let ctx = ConnectionContext(fd: fd)
        defer {
            ctx.performCleanup()
            close(fd)
        }
        while true {
            var buffer = Data()
            var byte: UInt8 = 0
            var sawAnyByte = false
            while true {
                let n = read(fd, &byte, 1)
                if n <= 0 {
                    if !sawAnyByte { return }
                    break
                }
                sawAnyByte = true
                if byte == 0x0A { break }
                buffer.append(byte)
            }
            if buffer.isEmpty && !sawAnyByte { return }
            let response = handler(buffer, ctx)
            if !response.isEmpty {
                ctx.write(response)
            }
        }
    }
}

