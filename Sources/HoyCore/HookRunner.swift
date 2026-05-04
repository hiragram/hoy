import Foundation

// ADR 0016: agent-dispatch hook の実行。
// `<root>/hooks/<event>.sh` が存在すれば JSON payload を stdin に流して実行。
// 失敗は無視 (daemon の動作を妨げない)。
public final class HookRunner: @unchecked Sendable {
    public let hooksDir: String

    public init(workspaceRoot: String) {
        self.hooksDir = (workspaceRoot as NSString).appendingPathComponent("hooks")
    }

    public func fire(event: String, payload: [String: Any]) {
        let scriptPath = (hooksDir as NSString).appendingPathComponent("\(event).sh")
        guard FileManager.default.fileExists(atPath: scriptPath) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptPath]

        let inPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        var enriched = payload
        enriched["event"] = event
        let data = (try? JSONSerialization.data(withJSONObject: enriched)) ?? Data("{}".utf8)
        do {
            try process.run()
            inPipe.fileHandleForWriting.write(data)
            try? inPipe.fileHandleForWriting.close()
            // 非ブロッキング — 終了を待たない
        } catch {
            // hook の起動失敗は無視
        }
    }
}
