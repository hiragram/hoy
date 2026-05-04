import Foundation

public enum TaskServiceError: Error, Equatable {
    case taskNotFound(String)
    case noCompletedShaToRevert
    case integrationConflict(stderr: String)
    case nothingToCommit
}

// ADR 0014: Task 完了時の即時統合。
// ADR 0034: revert は一級操作 (裏で git revert)。
// ADR 0045: Task は専用 worktree で作業し、complete 時に main へ rebase + ff 統合する。
public final class TaskService {
    private let workspace: Workspace

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    public struct CompletionResult: Equatable {
        public let task: HoyTask
        public let sha: String
        public let invalidatedTaskIds: [String]
    }

    /// task 用 worktree のパスを返す (作成済 / 未作成は問わず deterministic)。
    public func workspacePath(forTask taskId: String) -> String {
        return workspace.worktrees.worktreePath(forTask: taskId)
    }

    /// task 用 worktree を作成する (idempotent: 既存ならそのまま path を返す)。
    @discardableResult
    public func ensureWorktree(forTask taskId: String) throws -> String {
        let path = workspace.worktrees.worktreePath(forTask: taskId)
        if FileManager.default.fileExists(atPath: path) { return path }
        return try workspace.worktrees.create(taskId: taskId)
    }

    /// task の worktree 内の変更を commit、main へ rebase + ff 統合する。
    /// `commitChanges = false` ではメタデータのみ完了させる。
    /// `bypassVerifications = true` で必須検証経路 gate を飛び越す。
    public func complete(
        task: HoyTask,
        by actor: PrincipalRef,
        commitChanges: Bool = true,
        bypassVerifications: Bool = false,
        now: Date = Date()
    ) throws -> CompletionResult {
        // 検証経路 gate を先に確認 (commit や worktree 操作より前に弾く)
        if !bypassVerifications {
            guard VerificationGate.allRequiredSatisfied(in: task.verifications) else {
                throw HoyTaskError.verificationsNotSatisfied
            }
        }

        let sha: String?
        if commitChanges {
            // worktree が無ければ作る (lazy)
            let wtPath = try ensureWorktree(forTask: task.id)
            let wtGit = Git(workdir: wtPath)
            // worktree 内の変更を commit (空コミットは許さない)
            do {
                _ = try wtGit.commitAll(message: "task: \(task.title)", allowEmpty: false)
            } catch GitError.nothingToCommit {
                throw TaskServiceError.nothingToCommit
            }
            // main に rebase + ff 統合
            do {
                sha = try workspace.worktrees.integrate(taskId: task.id)
            } catch let WorktreeManagerError.rebaseConflict(stderr) {
                workspace.hooks.fire(event: "conflict.detected", payload: [
                    "taskId": task.id, "intentId": task.intentId,
                    "stderr": stderr
                ])
                throw TaskServiceError.integrationConflict(stderr: stderr)
            }
            // 統合済みなので worktree は不要
            try? workspace.worktrees.remove(taskId: task.id)
        } else {
            sha = nil
        }
        let completed = try task.complete(sha: sha, bypassVerifications: bypassVerifications)
        try workspace.tasks.save(completed)

        // ADR 0017: main が動いた (commitChanges=true で integrate 成功) 場合、
        // 他の open / claimed / inProgress な task の automated check を
        // pending に戻す。検証経路再走を要請する。
        var invalidated: [String] = []
        if commitChanges && sha != nil {
            let openStatuses: Set<HoyTask.Status> = [.open, .claimed, .inProgress]
            for other in try workspace.tasks.list() where other.id != task.id {
                guard openStatuses.contains(other.status) else { continue }
                let updated = other.verifications.map { $0.resetToPending() }
                if updated != other.verifications {
                    try workspace.tasks.save(other.replacingVerifications(updated))
                    invalidated.append(other.id)
                }
            }
        }

        var payload: [String: String] = [
            "taskId": task.id, "intentId": task.intentId
        ]
        if let sha { payload["sha"] = sha }
        try workspace.audit.append(AuditEntry.record(
            actor: actor, op: "task.complete", payload: payload, now: now
        ))
        try? workspace.storage.checkpoint()
        workspace.hooks.fire(event: "task.completed", payload: payload)
        return CompletionResult(task: completed, sha: sha ?? "", invalidatedTaskIds: invalidated)
    }

    public struct CloseResult: Equatable {
        public let task: HoyTask
    }

    /// Task を closed に遷移させる。完了/revert と区別される「畳む」操作。
    public func close(
        taskId: String,
        by actor: PrincipalRef,
        reason: String,
        now: Date = Date()
    ) throws -> CloseResult {
        guard let task = try workspace.tasks.get(id: taskId) else {
            throw TaskServiceError.taskNotFound(taskId)
        }
        let closed = try task.close()
        try workspace.tasks.save(closed)
        try workspace.audit.append(AuditEntry.record(
            actor: actor,
            op: "task.close",
            payload: [
                "taskId": task.id, "intentId": task.intentId, "reason": reason
            ],
            now: now
        ))
        return CloseResult(task: closed)
    }

    public struct RevertResult: Equatable {
        public let task: HoyTask
        public let revertSha: String
    }

    /// completed Task を reverted に遷移させ、対応する完了コミットを git revert する。
    public func revert(
        taskId: String,
        by actor: PrincipalRef,
        now: Date = Date()
    ) throws -> RevertResult {
        guard let task = try workspace.tasks.get(id: taskId) else {
            throw TaskServiceError.taskNotFound(taskId)
        }
        guard let originalSha = task.completedSha else {
            throw TaskServiceError.noCompletedShaToRevert
        }
        let revertSha = try workspace.git.revert(sha: originalSha)
        let reverted = try task.revert()
        try workspace.tasks.save(reverted)
        try workspace.audit.append(AuditEntry.record(
            actor: actor,
            op: "task.revert",
            payload: [
                "taskId": task.id,
                "intentId": task.intentId,
                "originalSha": originalSha,
                "revertSha": revertSha
            ],
            now: now
        ))
        try? workspace.storage.checkpoint()
        workspace.hooks.fire(event: "task.reverted", payload: [
            "taskId": task.id, "intentId": task.intentId,
            "originalSha": originalSha, "revertSha": revertSha
        ])
        return RevertResult(task: reverted, revertSha: revertSha)
    }
}
