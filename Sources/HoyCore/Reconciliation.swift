import Foundation

// ADR 0035: Git と SQLite の乖離を検知する。MVP は最小限。

public struct ReconciliationReport: Equatable {
    public var missingShas: [String]    // SQLite が指す sha が git に存在しない
    public var orphanCommits: [String]  // git main にあるが SQLite から参照されないコミット
    public var unfinishedWorktrees: [String]  // <root>/worktrees/ に残ったまま task が完了済の worktree

    public var isClean: Bool {
        return missingShas.isEmpty && orphanCommits.isEmpty && unfinishedWorktrees.isEmpty
    }
}

public final class Reconciliation {
    private let workspace: Workspace

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    public func check() throws -> ReconciliationReport {
        var missing: [String] = []
        var referenced = Set<String>()
        let allTasks = try workspace.tasks.list()
        for task in allTasks {
            guard let sha = task.completedSha else { continue }
            referenced.insert(sha)
            let result = try workspace.git.run(["cat-file", "-t", sha])
            if !result.succeeded {
                missing.append(sha)
            }
        }

        // main の commit 履歴 vs SQLite が参照する sha。
        // hoy が作った commit (subject が "task: " で始まる) のうち、
        // task から参照されないものだけを orphan とする。
        // ユーザが手で打った commit はノイズになるため対象外。
        var orphans: [String] = []
        let logResult = try workspace.git.run(["log", "--format=%H%x09%s", "main"])
        if logResult.succeeded {
            for line in logResult.stdout.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let sha = parts[0]
                let subject = parts[1]
                guard subject.hasPrefix("task: ") else { continue }
                if referenced.contains(sha) { continue }
                orphans.append(sha)
            }
        }

        // 完了済タスクの worktree が残っていないか
        var unfinished: [String] = []
        let worktreesDir = (workspace.root as NSString).appendingPathComponent("worktrees")
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: worktreesDir) {
            let completedTaskIds = Set(allTasks.filter { $0.status == .completed }.map { $0.id })
            for entry in entries where completedTaskIds.contains(entry) {
                unfinished.append(entry)
            }
        }

        return ReconciliationReport(
            missingShas: missing,
            orphanCommits: orphans,
            unfinishedWorktrees: unfinished
        )
    }

    /// 自動修復可能なものを修復する。MVP では:
    /// - unfinishedWorktrees: worktree を削除 (task は完了済なので統合は終わっている)
    /// missing/orphan は手動判断が要るため修復しない (報告のみ)。
    public func repair() throws -> ReconciliationReport {
        let report = try check()
        for taskId in report.unfinishedWorktrees {
            try? workspace.worktrees.remove(taskId: taskId)
        }
        return try check()
    }
}
