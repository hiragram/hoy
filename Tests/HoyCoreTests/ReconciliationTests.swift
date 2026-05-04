import Testing
import Foundation
@testable import HoyCore

struct ReconciliationTests {
    private let actor = PrincipalRef(id: "agent-1", kind: .agent)

    private func makeWorkspace() throws -> Workspace {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-rec-\(UUID().uuidString)")
        return try Workspace.open(at: root)
    }

    @Test func cleanWhenAllShasResolve() throws {
        let ws = try makeWorkspace()
        let svc = TaskService(workspace: ws)
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor)
        try ws.tasks.save(task)
        _ = try svc.complete(task: task, by: actor)

        let report = try Reconciliation(workspace: ws).check()
        #expect(report.isClean)
    }

    @Test func detectsMissingSha() throws {
        let ws = try makeWorkspace()
        let task = HoyTask(
            id: UUID().uuidString, intentId: "i", title: "x",
            createdBy: actor, status: .completed,
            dependsOn: [], verifications: [],
            completedSha: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        )
        try ws.tasks.save(task)
        let report = try Reconciliation(workspace: ws).check()
        #expect(report.missingShas.count == 1)
    }
}

struct BackupTests {
    private let actor = PrincipalRef(id: "agent-1", kind: .agent)

    @Test func snapshot_copiesDbAndRepo() throws {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-bk-\(UUID().uuidString)")
        let ws = try Workspace.open(at: root)
        let dest = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-bk-dest-\(UUID().uuidString)")
        let dir = try Backup(workspace: ws).snapshot(to: dest)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: (dir as NSString).appendingPathComponent("state.db")))
        #expect(fm.fileExists(atPath: (dir as NSString).appendingPathComponent("repo/.git")))
    }
}
