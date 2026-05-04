import Testing
import Foundation
@testable import HoyCore

struct TaskRepositoryTests {
    private let principal = PrincipalRef(id: "agent-1", kind: .agent)

    private func makeRepo() throws -> TaskRepository {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-\(UUID().uuidString).sqlite")
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        return TaskRepository(storage: storage)
    }

    @Test func roundTrip_basic() throws {
        let repo = try makeRepo()
        let task = HoyTask.create(intentId: "i", title: "do thing", createdBy: principal)
        try repo.save(task)
        let loaded = try repo.get(id: task.id)
        #expect(loaded == task)
    }

    @Test func roundTrip_withDependsOn() throws {
        let repo = try makeRepo()
        let dep = IntentRef(id: "i-9", version: 3)
        let task = HoyTask.create(
            intentId: "i",
            title: "x",
            createdBy: principal,
            dependsOn: [dep]
        )
        try repo.save(task)
        let loaded = try repo.get(id: task.id)
        #expect(loaded?.dependsOn == [dep])
    }

    @Test func roundTrip_withVerifications() throws {
        let repo = try makeRepo()
        let approver = PrincipalRef(id: "u1", kind: .human)
        let pending = VerificationCheck.automated(category: "unittest", command: "swift test")
        let waived = try VerificationCheck.human(category: "ux", instruction: "manual")
            .waive(reason: "low risk", by: approver)
        let task = HoyTask.create(
            intentId: "i",
            title: "x",
            createdBy: principal,
            verifications: [pending, waived]
        )
        try repo.save(task)
        let loaded = try repo.get(id: task.id)
        #expect(loaded?.verifications == [pending, waived])
    }

    @Test func update_replacesDependenciesAndVerifications() throws {
        let repo = try makeRepo()
        let v1 = HoyTask.create(
            intentId: "i",
            title: "x",
            createdBy: principal,
            dependsOn: [IntentRef(id: "old", version: 1)],
            verifications: [VerificationCheck.automated(category: "old", command: "x")]
        )
        try repo.save(v1)
        // 同じ id で上書き(status 遷移は別途、ここではシンプルに新しいタスクを作って差し替え)
        let v2 = HoyTask(
            id: v1.id,
            intentId: v1.intentId,
            title: v1.title,
            createdBy: v1.createdBy,
            status: v1.status,
            dependsOn: [IntentRef(id: "new", version: 2)],
            verifications: [],
            completedSha: nil
        )
        try repo.save(v2)
        let loaded = try repo.get(id: v1.id)
        #expect(loaded?.dependsOn == [IntentRef(id: "new", version: 2)])
        #expect(loaded?.verifications == [])
    }

    @Test func get_returnsNilForUnknown() throws {
        let repo = try makeRepo()
        #expect(try repo.get(id: "nope") == nil)
    }
}
