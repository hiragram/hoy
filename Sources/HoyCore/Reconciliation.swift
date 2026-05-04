import Foundation

// ADR 0035: Git と SQLite の乖離を検知する。MVP は最小限。

public struct ReconciliationReport: Equatable {
    public var missingShas: [String]   // SQLite が指す sha が git に存在しない
    public var orphanCommits: [String] // git にあるが SQLite から参照されないコミット (MVP では未対応)

    public var isClean: Bool { missingShas.isEmpty && orphanCommits.isEmpty }
}

public final class Reconciliation {
    private let workspace: Workspace

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    public func check() throws -> ReconciliationReport {
        var missing: [String] = []
        for task in try workspace.tasks.list() {
            guard let sha = task.completedSha else { continue }
            let result = try workspace.git.run(["cat-file", "-t", sha])
            if !result.succeeded {
                missing.append(sha)
            }
        }
        return ReconciliationReport(missingShas: missing, orphanCommits: [])
    }
}
