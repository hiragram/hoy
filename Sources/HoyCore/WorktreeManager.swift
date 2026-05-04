import Foundation

public enum WorktreeManagerError: Error, Equatable {
    case alreadyExists(String)
    case rebaseConflict(stderr: String)
}

/// ADR 0045: Task ごとに git worktree を切る運用を担うマネージャ。
/// `<root>/worktrees/<taskId>/` 配下に worktree を作り、`task/<taskId>` ブランチを切る。
public final class WorktreeManager {
    private let workspaceRoot: String
    private let mainGit: Git

    public init(workspaceRoot: String, mainGit: Git) {
        self.workspaceRoot = workspaceRoot
        self.mainGit = mainGit
    }

    public func worktreePath(forTask taskId: String) -> String {
        let worktreesDir = (workspaceRoot as NSString).appendingPathComponent("worktrees")
        return (worktreesDir as NSString).appendingPathComponent(taskId)
    }

    public func branchName(forTask taskId: String) -> String {
        return "task/\(taskId)"
    }

    /// task 用 worktree を作成する。既存なら `alreadyExists`。
    public func create(taskId: String, baseBranch: String = "main") throws -> String {
        let path = worktreePath(forTask: taskId)
        if FileManager.default.fileExists(atPath: path) {
            throw WorktreeManagerError.alreadyExists(path)
        }
        let worktreesDir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: worktreesDir, withIntermediateDirectories: true)
        try mainGit.worktreeAdd(
            path: path, branch: branchName(forTask: taskId), base: baseBranch
        )
        return path
    }

    /// task の worktree を `target` ブランチに rebase し、成功したら main を fast-forward する。
    /// 戻り値は統合後の main の sha。
    /// 失敗時は worktree を rebase --abort で戻し、`rebaseConflict` を投げる。
    public func integrate(taskId: String, ontoBranch target: String = "main") throws -> String {
        let wt = worktreePath(forTask: taskId)
        let branch = branchName(forTask: taskId)
        let worktreeGit = Git(workdir: wt)

        // 1) task ブランチを target に rebase
        let result = try worktreeGit.run(["rebase", target])
        if !result.succeeded {
            try? worktreeGit.run(["rebase", "--abort"])
            throw WorktreeManagerError.rebaseConflict(stderr: result.stderr)
        }

        // 2) main を fast-forward
        try mainGit.runChecked(["merge", "--ff-only", branch])

        // 3) main の現在の sha
        return try mainGit.currentSha()
    }

    /// worktree とブランチを削除する。完了後の cleanup に使う。
    public func remove(taskId: String) throws {
        let wt = worktreePath(forTask: taskId)
        let branch = branchName(forTask: taskId)
        if FileManager.default.fileExists(atPath: wt) {
            try mainGit.worktreeRemove(path: wt, force: true)
        }
        // ブランチ削除は失敗してもよい (既に消えてるケース)
        try? mainGit.branchDelete(branch, force: true)
    }
}
