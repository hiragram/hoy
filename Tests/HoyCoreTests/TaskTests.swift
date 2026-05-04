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
}
