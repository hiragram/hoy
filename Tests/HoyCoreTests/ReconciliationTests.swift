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

    @Test func restore_recreatesDbAndRepo() throws {
        let actor = PrincipalRef(id: "u", kind: .human)
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-rs-\(UUID().uuidString)")
        let ws = try Workspace.open(at: root)
        let intent = Intent.create(title: "before backup")
        try ws.intents.save(intent)

        let dest = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-rs-dest-\(UUID().uuidString)")
        let snap = try Backup(workspace: ws).snapshot(to: dest)

        let target = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-rs-target-\(UUID().uuidString)")
        try Backup.restore(from: snap, into: target)
        let restored = try Workspace.open(at: target)
        #expect(try restored.intents.latest(id: intent.id)?.title == "before backup")
        _ = actor
    }

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
