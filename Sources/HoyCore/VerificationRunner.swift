import Foundation

public enum VerificationRunnerError: Error, Equatable {
    case taskNotFound(String)
    case checkNotFound(String)
}

// ADR 0017: automated check は subprocess 実行、結果を evidence として保存。
// human check は外部承認待ち。本クラスはそのトランジションを束ねる。
public final class VerificationRunner {
    private let workspace: Workspace

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    /// 指定 Task の pending な automated check をすべて順に実行する。
    /// task の worktree が存在すればそこを cwd にする (worktree 内の未統合変更が
    /// テストから見えるように)。なければ main repo を cwd にフォールバック。
    /// 並列実行は open-questions #7 で MVP 後検討。
    @discardableResult
    public func runAutomated(taskId: String) throws -> HoyTask {
        guard let task = try workspace.tasks.get(id: taskId) else {
            throw VerificationRunnerError.taskNotFound(taskId)
        }
        let cwd = effectiveCwd(forTask: taskId)
        var updated = task.verifications
        for index in updated.indices {
            let check = updated[index]
            guard case .automated(let command) = check.kind else { continue }
            // pending か failed なら走らせる。failed は redObserved を保持しつつ
            // 内部で pending に戻して再 run。
            let runnable: VerificationCheck
            switch check.status {
            case .pending:
                runnable = check
            case .failed:
                runnable = check.prepareForRerun()
            default:
                continue
            }
            let result = try runShell(command, cwd: cwd)
            let evidence = "cwd \(cwd)\nexit \(result.exitCode)\n--- stdout ---\n\(result.stdout)\n--- stderr ---\n\(result.stderr)"
            updated[index] = result.exitCode == 0
                ? try runnable.markPassed(evidence: evidence)
                : try runnable.markFailed(evidence: evidence)
        }
        let next = task.replacingVerifications(updated)
        try workspace.tasks.save(next)
        return next
    }

    /// task の worktree が存在すればそのパスを返す。なければ main repo。
    private func effectiveCwd(forTask taskId: String) -> String {
        let wt = workspace.worktrees.worktreePath(forTask: taskId)
        if FileManager.default.fileExists(atPath: wt) { return wt }
        return repoPath()
    }

    public func recordHumanResult(
        taskId: String,
        checkId: String,
        passed: Bool,
        evidence: String
    ) throws -> HoyTask {
        return try mutateCheck(taskId: taskId, checkId: checkId) { check in
            return passed
                ? try check.markPassed(evidence: evidence)
                : try check.markFailed(evidence: evidence)
        }
    }

    public func waive(
        taskId: String,
        checkId: String,
        reason: String,
        by approver: PrincipalRef
    ) throws -> HoyTask {
        return try mutateCheck(taskId: taskId, checkId: checkId) { check in
            try check.waive(reason: reason, by: approver)
        }
    }

    private func mutateCheck(
        taskId: String,
        checkId: String,
        transform: (VerificationCheck) throws -> VerificationCheck
    ) throws -> HoyTask {
        guard let task = try workspace.tasks.get(id: taskId) else {
            throw VerificationRunnerError.taskNotFound(taskId)
        }
        guard let idx = task.verifications.firstIndex(where: { $0.id == checkId }) else {
            throw VerificationRunnerError.checkNotFound(checkId)
        }
        var updated = task.verifications
        updated[idx] = try transform(updated[idx])
        let next = task.replacingVerifications(updated)
        try workspace.tasks.save(next)
        return next
    }

    private func repoPath() -> String {
        return (workspace.root as NSString).appendingPathComponent("repo")
    }

    private struct ShellResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func runShell(_ command: String, cwd: String) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ) ?? ""
        return ShellResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

extension HoyTask {
    public func replacingVerifications(_ next: [VerificationCheck]) -> HoyTask {
        return HoyTask(
            id: id,
            intentId: intentId,
            title: title,
            createdBy: createdBy,
            status: status,
            dependsOn: dependsOn,
            verifications: next,
            completedSha: completedSha
        )
    }

    public func appendingVerification(_ check: VerificationCheck) -> HoyTask {
        return replacingVerifications(verifications + [check])
    }
}
