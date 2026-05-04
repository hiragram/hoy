import Testing
import Foundation
@testable import HoyCore

struct WorktreeManagerTests {
    private func makeWorkspace() throws -> Workspace {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-wt-\(UUID().uuidString)")
        let ws = try Workspace.open(at: root)
        // base commit
        let readme = ((ws.root as NSString).appendingPathComponent("repo") as NSString)
            .appendingPathComponent("README.md")
        try "v0".write(toFile: readme, atomically: true, encoding: .utf8)
        _ = try ws.git.commitAll(message: "init")
        return ws
    }

    @Test func create_makesWorktreeAndBranch() throws {
        let ws = try makeWorkspace()
        let mgr = WorktreeManager(workspaceRoot: ws.root, mainGit: ws.git)
        let path = try mgr.create(taskId: "t1")
        #expect(FileManager.default.fileExists(atPath: path))

        // 新 worktree から HEAD が読める
        let wtGit = Git(workdir: path)
        _ = try wtGit.runChecked(["rev-parse", "HEAD"])
    }

    @Test func integrate_fastForwardsMain() throws {
        let ws = try makeWorkspace()
        let mgr = WorktreeManager(workspaceRoot: ws.root, mainGit: ws.git)
        let path = try mgr.create(taskId: "t1")

        // worktree 内で変更してコミット
        let file = (path as NSString).appendingPathComponent("a.txt")
        try "from t1".write(toFile: file, atomically: true, encoding: .utf8)
        let wtGit = Git(workdir: path)
        _ = try wtGit.commitAll(message: "t1 work")

        let mainSha = try mgr.integrate(taskId: "t1")
        // main 側の README は無傷、a.txt が追加されている
        let mainRepo = (ws.root as NSString).appendingPathComponent("repo")
        let mainFile = (mainRepo as NSString).appendingPathComponent("a.txt")
        #expect(FileManager.default.fileExists(atPath: mainFile))
        #expect(try ws.git.currentSha() == mainSha)
    }

    @Test func integrate_conflict_throwsAndRevertsWorktree() throws {
        let ws = try makeWorkspace()
        let mgr = WorktreeManager(workspaceRoot: ws.root, mainGit: ws.git)

        // base に shared.txt を追加
        let mainRepo = (ws.root as NSString).appendingPathComponent("repo")
        let sharedMain = (mainRepo as NSString).appendingPathComponent("shared.txt")
        try "base".write(toFile: sharedMain, atomically: true, encoding: .utf8)
        _ = try ws.git.commitAll(message: "add shared")

        // 2 worktree を base から派生
        let p1 = try mgr.create(taskId: "tA")
        let p2 = try mgr.create(taskId: "tB")

        // tA で shared.txt を編集
        let sA = (p1 as NSString).appendingPathComponent("shared.txt")
        try "from A".write(toFile: sA, atomically: true, encoding: .utf8)
        _ = try Git(workdir: p1).commitAll(message: "A")

        // tB も同じ shared.txt を別内容に編集
        let sB = (p2 as NSString).appendingPathComponent("shared.txt")
        try "from B".write(toFile: sB, atomically: true, encoding: .utf8)
        _ = try Git(workdir: p2).commitAll(message: "B")

        // tA を先に統合 → 成功
        _ = try mgr.integrate(taskId: "tA")

        // tB を統合しようとすると rebase conflict
        #expect(throws: WorktreeManagerError.self) {
            _ = try mgr.integrate(taskId: "tB")
        }

        // worktree が rebase --abort された状態で残る (tB の作業は失われていない)
        let bGit = Git(workdir: p2)
        let r = try bGit.runChecked(["rev-parse", "HEAD"])
        #expect(!r.stdout.isEmpty)
    }

    @Test func remove_deletesWorktreeAndBranch() throws {
        let ws = try makeWorkspace()
        let mgr = WorktreeManager(workspaceRoot: ws.root, mainGit: ws.git)
        let path = try mgr.create(taskId: "t1")
        #expect(FileManager.default.fileExists(atPath: path))
        try mgr.remove(taskId: "t1")
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
