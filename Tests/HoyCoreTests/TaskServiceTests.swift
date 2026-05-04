import Testing
import Foundation
@testable import HoyCore

struct TaskServiceTests {
    private let actor = PrincipalRef(id: "agent-1", kind: .agent)

    private func makeWorkspace() throws -> Workspace {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-svc-\(UUID().uuidString)")
        return try Workspace.open(at: root)
    }

    private func writeInWorktree(_ ws: Workspace, taskId: String, name: String, content: String) throws {
        let svc = TaskService(workspace: ws)
        let path = try svc.ensureWorktree(forTask: taskId)
        let file = (path as NSString).appendingPathComponent(name)
        try content.write(toFile: file, atomically: true, encoding: .utf8)
    }

    @Test func complete_integratesWorktreeIntoMain() throws {
        let ws = try makeWorkspace()
        let svc = TaskService(workspace: ws)
        let task = HoyTask.create(intentId: "i-1", title: "ship", createdBy: actor)
        try ws.tasks.save(task)

        try writeInWorktree(ws, taskId: task.id, name: "out.txt", content: "done")
        let result = try svc.complete(task: task, by: actor)

        #expect(result.task.status == .completed)
        #expect(result.task.completedSha == result.sha)
        #expect(result.sha.count == 40)

        // main 側に file が反映されている
        let mainRepo = (ws.root as NSString).appendingPathComponent("repo")
        let mainFile = (mainRepo as NSString).appendingPathComponent("out.txt")
        #expect(FileManager.default.fileExists(atPath: mainFile))

        // worktree は cleanup されている
        let wt = svc.workspacePath(forTask: task.id)
        #expect(!FileManager.default.fileExists(atPath: wt))

        let loaded = try ws.tasks.get(id: task.id)
        #expect(loaded?.status == .completed)

        let audit = try ws.audit.all()
        #expect(audit.contains { $0.op == "task.complete" && $0.payload["taskId"] == task.id })
    }

    @Test func complete_blockedByPendingVerification() throws {
        let ws = try makeWorkspace()
        let svc = TaskService(workspace: ws)
        let pending = VerificationCheck.automated(category: "unittest", command: "x")
        let task = HoyTask.create(
            intentId: "i", title: "x", createdBy: actor,
            verifications: [pending]
        )
        try ws.tasks.save(task)
        #expect(throws: HoyTaskError.verificationsNotSatisfied) {
            try svc.complete(task: task, by: actor)
        }
    }

    @Test func complete_conflict_throwsAndPreservesWorktree() throws {
        let ws = try makeWorkspace()
        let svc = TaskService(workspace: ws)

        // base に shared を追加してコミット (main を進める)
        let mainRepo = (ws.root as NSString).appendingPathComponent("repo")
        let sharedMain = (mainRepo as NSString).appendingPathComponent("shared.txt")
        try "base".write(toFile: sharedMain, atomically: true, encoding: .utf8)
        _ = try ws.git.commitAll(message: "base")

        // 2 task を base から派生
        let tA = HoyTask.create(intentId: "iA", title: "A", createdBy: actor)
        let tB = HoyTask.create(intentId: "iB", title: "B", createdBy: actor)
        try ws.tasks.save(tA)
        try ws.tasks.save(tB)

        try writeInWorktree(ws, taskId: tA.id, name: "shared.txt", content: "from A")
        try writeInWorktree(ws, taskId: tB.id, name: "shared.txt", content: "from B")

        // A を統合 → 成功
        _ = try svc.complete(task: tA, by: actor)

        // B を統合 → conflict
        var conflictRaised = false
        do {
            _ = try svc.complete(task: tB, by: actor)
        } catch TaskServiceError.integrationConflict {
            conflictRaised = true
        }
        #expect(conflictRaised)

        // tB の worktree は残っており、状態は rebase --abort 後 (作業ロスなし)
        let wtB = svc.workspacePath(forTask: tB.id)
        #expect(FileManager.default.fileExists(atPath: wtB))
    }

    @Test func revert_appliesGitRevertAndUpdatesTask() throws {
        let ws = try makeWorkspace()
        let svc = TaskService(workspace: ws)
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor)
        try ws.tasks.save(task)
        try writeInWorktree(ws, taskId: task.id, name: "a.txt", content: "added by task")
        let completed = try svc.complete(task: task, by: actor)

        let result = try svc.revert(taskId: task.id, by: actor)
        #expect(result.task.status == .reverted)
        #expect(result.revertSha != completed.sha)

        let repoPath = (ws.root as NSString).appendingPathComponent("repo")
        let file = (repoPath as NSString).appendingPathComponent("a.txt")
        #expect(!FileManager.default.fileExists(atPath: file))

        let audit = try ws.audit.all()
        #expect(audit.contains { $0.op == "task.revert" })
    }

    @Test func revert_taskNotFoundThrows() throws {
        let ws = try makeWorkspace()
        let svc = TaskService(workspace: ws)
        #expect(throws: TaskServiceError.taskNotFound("missing")) {
            try svc.revert(taskId: "missing", by: actor)
        }
    }
}
