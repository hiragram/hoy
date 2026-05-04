import Foundation

public struct GitResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var succeeded: Bool { exitCode == 0 }
}

public enum GitError: Error, Equatable {
    case nonZeroExit(args: [String], result: GitResult)
    case launchFailed(String)
}

// ADR 0013, 0036: 内部 Git は subprocess 経由で操作する。
public struct Git {
    public let workdir: String
    public let executable: String

    public init(workdir: String, executable: String = "/usr/bin/env") {
        self.workdir = workdir
        self.executable = executable
    }

    @discardableResult
    public func run(_ args: [String]) throws -> GitResult {
        let process = Process()
        // /usr/bin/env git ARGS で PATH 解決を借りる
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(String(describing: error))
        }
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return GitResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus
        )
    }

    @discardableResult
    public func runChecked(_ args: [String]) throws -> GitResult {
        let result = try run(args)
        guard result.succeeded else {
            throw GitError.nonZeroExit(args: args, result: result)
        }
        return result
    }

    // MARK: - 高レベル操作

    /// 作業ディレクトリに通常リポジトリを初期化する。既に初期化済みなら何もしない。
    public func initIfNeeded(initialBranch: String = "main") throws {
        let gitDir = (workdir as NSString).appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir) { return }
        try runChecked(["init", "--initial-branch=\(initialBranch)"])
        try runChecked(["config", "user.email", "hoy@localhost"])
        try runChecked(["config", "user.name", "hoy"])
    }

    /// 作業ツリーをすべて add してコミット。空コミットは許可。
    /// 戻り値はコミット SHA。
    @discardableResult
    public func commitAll(message: String, allowEmpty: Bool = true) throws -> String {
        try runChecked(["add", "-A"])
        var args = ["commit", "-m", message]
        if allowEmpty { args.append("--allow-empty") }
        try runChecked(args)
        let result = try runChecked(["rev-parse", "HEAD"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 指定 SHA を revert する。新しいコミット SHA を返す。
    @discardableResult
    public func revert(sha: String, message: String? = nil) throws -> String {
        var args = ["revert", "--no-edit", sha]
        if let message {
            args = ["revert", "--no-edit", "-m", "1", sha]
            _ = message  // -m on revert は merge 用。message override は別途必要なら git commit --amend
        }
        try runChecked(args)
        let result = try runChecked(["rev-parse", "HEAD"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func currentSha() throws -> String {
        let result = try runChecked(["rev-parse", "HEAD"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 指定ブランチへの rebase。コンフリクトが起きた場合は非ゼロ exit が返る。
    /// 呼び出し側が GitError をハンドルし、必要なら abort して上位へエスカレート。
    public func rebase(onto branch: String) throws -> GitResult {
        return try run(["rebase", branch])
    }

    public func rebaseAbort() throws {
        try runChecked(["rebase", "--abort"])
    }
}
