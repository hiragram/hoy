import Testing
@testable import HoyCore

struct TaskTests {
    private let principal = PrincipalRef(id: "u1", kind: .human)

    // ADR 0001: Task は必ず Intent に紐づく
    @Test func create_assignsNonEmptyId() {
        let task = HoyTask.create(intentId: "intent-1", title: "do thing", createdBy: principal)
        #expect(!task.id.isEmpty)
    }

    @Test func create_assignsUniqueIdPerCall() {
        let a = HoyTask.create(intentId: "intent-1", title: "a", createdBy: principal)
        let b = HoyTask.create(intentId: "intent-1", title: "b", createdBy: principal)
        #expect(a.id != b.id)
    }

    @Test func create_retainsIntentIdAndTitle() {
        let task = HoyTask.create(intentId: "intent-42", title: "ship", createdBy: principal)
        #expect(task.intentId == "intent-42")
        #expect(task.title == "ship")
    }

    // ADR 0006: created_by を保持
    @Test func create_retainsCreator() {
        let agent = PrincipalRef(id: "claude", kind: .agent)
        let task = HoyTask.create(intentId: "intent-1", title: "x", createdBy: agent)
        #expect(task.createdBy == agent)
    }

    // 起票時の status は open
    @Test func create_initialStatusIsOpen() {
        let task = HoyTask.create(intentId: "intent-1", title: "x", createdBy: principal)
        #expect(task.status == .open)
    }

    // ADR 0018: 依存は Intent@version で表現
    @Test func create_dependsOnDefaultsToEmpty() {
        let task = HoyTask.create(intentId: "intent-1", title: "x", createdBy: principal)
        #expect(task.dependsOn == [])
    }

    @Test func create_retainsDependsOn() {
        let dep = IntentRef(id: "intent-9", version: 3)
        let task = HoyTask.create(
            intentId: "intent-1",
            title: "x",
            createdBy: principal,
            dependsOn: [dep]
        )
        #expect(task.dependsOn == [dep])
    }

    // ADR 0014: Task 完了
    @Test func complete_transitionsOpenToCompleted() throws {
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: principal)
        let completed = try task.complete(sha: "deadbeef")
        #expect(completed.status == .completed)
        #expect(completed.id == task.id)
    }

    @Test func complete_alreadyCompletedThrows() throws {
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: principal)
        let completed = try task.complete(sha: "deadbeef")
        #expect(throws: HoyTaskError.invalidTransition) {
            try completed.complete(sha: "x")
        }
    }

    // ADR 0034: completed -> reverted は一級遷移
    @Test func revert_transitionsCompletedToReverted() throws {
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: principal)
        let completed = try task.complete(sha: "deadbeef")
        let reverted = try completed.revert()
        #expect(reverted.status == .reverted)
        #expect(reverted.id == task.id)
    }

    @Test func revert_nonCompletedThrows() throws {
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: principal)
        #expect(throws: HoyTaskError.invalidTransition) {
            try task.revert()
        }
    }

    // 必須検証経路が未通過なら complete を拒否
    @Test func complete_blockedByPendingRequiredVerification() throws {
        let pending = VerificationCheck.automated(category: "unittest", command: "x")
        let task = HoyTask.create(
            intentId: "i",
            title: "x",
            createdBy: principal,
            verifications: [pending]
        )
        #expect(throws: HoyTaskError.verificationsNotSatisfied) {
            try task.complete(sha: "deadbeef")
        }
    }

    @Test func complete_passesWhenRequiredSatisfied() throws {
        let passed = try VerificationCheck.automated(category: "unittest", command: "x")
            .markPassed(evidence: "ok")
        let task = HoyTask.create(
            intentId: "i",
            title: "x",
            createdBy: principal,
            verifications: [passed]
        )
        let completed = try task.complete(sha: "deadbeef")
        #expect(completed.status == .completed)
    }
}
