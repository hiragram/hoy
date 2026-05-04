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

    private func writeFile(_ ws: Workspace, name: String, content: String) throws {
        let repo = (ws.root as NSString).appendingPathComponent("repo")
        let file = (repo as NSString).appendingPathComponent(name)
        try content.write(toFile: file, atomically: true, encoding: .utf8)
    }

    @Test func complete_commitsAndUpdatesTask() throws {
        let ws = try makeWorkspace()
        let svc = TaskService(workspace: ws)
        let task = HoyTask.create(intentId: "i-1", title: "ship", createdBy: actor)
        try ws.tasks.save(task)

        try writeFile(ws, name: "out.txt", content: "done")
        let result = try svc.complete(task: task, by: actor)

        #expect(result.task.status == .completed)
        #expect(result.task.completedSha == result.sha)
        #expect(result.sha.count == 40)

        let loaded = try ws.tasks.get(id: task.id)
        #expect(loaded?.status == .completed)
        #expect(loaded?.completedSha == result.sha)

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

    @Test func revert_appliesGitRevertAndUpdatesTask() throws {
        let ws = try makeWorkspace()
        let svc = TaskService(workspace: ws)
        // 初期コミットを作っておく(空コミットだと revert 対象がない)
        _ = try ws.git.commitAll(message: "init")
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor)
        try ws.tasks.save(task)
        try writeFile(ws, name: "a.txt", content: "added by task")
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
