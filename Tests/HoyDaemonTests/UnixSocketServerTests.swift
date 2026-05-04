import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import HoyDaemon

struct UnixSocketServerTests {
    private func socketPath() -> String {
        return (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-sock-\(UUID().uuidString)")
    }

    @Test func echo_roundTrip() throws {
        let path = socketPath()
        let server = UnixSocketServer(path: path)
        try server.start { req, _ in
            // echo
            var resp = Data("echo: ".utf8)
            resp.append(req)
            return resp
        }
        defer { server.stop() }

        // 起動完了を待つ簡易リトライ
        let response = try sendAndReceive(path: path, payload: "hello")
        #expect(response == "echo: hello")
    }

    @Test func socketFile_hasRestrictivePermissions() throws {
        let path = socketPath()
        let server = UnixSocketServer(path: path)
        try server.start { _, _ in Data() }
        defer { server.stop() }

        var st = stat()
        let r = stat(path, &st)
        #expect(r == 0)
        let mode = st.st_mode & 0o777
        #expect(mode == 0o600)
    }

    private func sendAndReceive(path: String, payload: String) throws -> String {
        // 数回リトライ (start は別スレッドで accept ループに入る)
        var lastErr: Int32 = 0
        for _ in 0..<10 {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            #expect(fd >= 0)

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
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
            if rc != 0 {
                lastErr = errno
                close(fd)
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            // 送信
            var data = Data(payload.utf8)
            data.append(0x0A)
            data.withUnsafeBytes { raw in
                _ = write(fd, raw.baseAddress, data.count)
            }
            // 受信 (最大 4KB)
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &buf, buf.count)
            close(fd)
            if n <= 0 { continue }
            var received = Data(bytes: buf, count: n)
            // 末尾の改行を除去
            if received.last == 0x0A { received.removeLast() }
            return String(data: received, encoding: .utf8) ?? ""
        }
        Issue.record("failed to connect, last errno=\(lastErr)")
        return ""
    }
}
