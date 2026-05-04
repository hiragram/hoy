import Foundation

public enum TaskServiceError: Error, Equatable {
    case taskNotFound(String)
    case noCompletedShaToRevert
}

// ADR 0014: Task 完了時の即時統合。
// ADR 0034: revert は一級操作 (裏で git revert)。
public final class TaskService {
    private let workspace: Workspace

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    public struct CompletionResult: Equatable {
        public let task: HoyTask
        public let sha: String
    }

    /// 作業ツリーの未コミット変更を `task: <title>` メッセージでコミットし、
    /// Task の status を completed に遷移、audit ログを書く。
    /// `commitChanges = false` を渡すと git commit を行わずメタデータのみ更新する
    /// (sha は記録されない、内部メタタスク向け)。
    public func complete(
        task: HoyTask,
        by actor: PrincipalRef,
        commitChanges: Bool = true,
        now: Date = Date()
    ) throws -> CompletionResult {
        let sha: String?
        if commitChanges {
            sha = try workspace.git.commitAll(
                message: "task: \(task.title)",
                allowEmpty: true
            )
        } else {
            sha = nil
        }
        let completed = try task.complete(sha: sha)
        try workspace.tasks.save(completed)
        var payload: [String: String] = [
            "taskId": task.id, "intentId": task.intentId
        ]
        if let sha { payload["sha"] = sha }
        try workspace.audit.append(AuditEntry.record(
            actor: actor, op: "task.complete", payload: payload, now: now
        ))
        workspace.hooks.fire(event: "task.completed", payload: payload)
        return CompletionResult(task: completed, sha: sha ?? "")
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
        workspace.hooks.fire(event: "task.reverted", payload: [
            "taskId": task.id, "intentId": task.intentId,
            "originalSha": originalSha, "revertSha": revertSha
        ])
        return RevertResult(task: reverted, revertSha: revertSha)
    }
}
