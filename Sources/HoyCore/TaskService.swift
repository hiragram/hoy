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
    public func complete(
        task: HoyTask,
        by actor: PrincipalRef,
        now: Date = Date()
    ) throws -> CompletionResult {
        let sha = try workspace.git.commitAll(
            message: "task: \(task.title)",
            allowEmpty: true
        )
        let completed = try task.complete(sha: sha)
        try workspace.tasks.save(completed)
        try workspace.audit.append(AuditEntry.record(
            actor: actor,
            op: "task.complete",
            payload: [
                "taskId": task.id,
                "intentId": task.intentId,
                "sha": sha
            ],
            now: now
        ))
        workspace.hooks.fire(event: "task.completed", payload: [
            "taskId": task.id, "intentId": task.intentId, "sha": sha
        ])
        return CompletionResult(task: completed, sha: sha)
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
