import Testing
import Foundation
@testable import HoyCore

struct VerificationRunnerTests {
    private let actor = PrincipalRef(id: "agent-1", kind: .agent)
    private let approver = PrincipalRef(id: "u1", kind: .human)

    private func makeWorkspace() throws -> Workspace {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-vr-\(UUID().uuidString)")
        return try Workspace.open(at: root)
    }

    @Test func runAutomated_passingCommandMarksPassed() throws {
        let ws = try makeWorkspace()
        let runner = VerificationRunner(workspace: ws)
        let check = VerificationCheck.automated(category: "smoke", command: "true")
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor, verifications: [check])
        try ws.tasks.save(task)

        let updated = try runner.runAutomated(taskId: task.id)
        #expect(updated.verifications.first?.status == .passed)
        #expect((updated.verifications.first?.evidence ?? "").contains("exit 0"))
    }

    @Test func runAutomated_failingCommandMarksFailed() throws {
        let ws = try makeWorkspace()
        let runner = VerificationRunner(workspace: ws)
        let check = VerificationCheck.automated(category: "smoke", command: "false")
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor, verifications: [check])
        try ws.tasks.save(task)

        let updated = try runner.runAutomated(taskId: task.id)
        #expect(updated.verifications.first?.status == .failed)
    }

    @Test func runAutomated_skipsHumanChecks() throws {
        let ws = try makeWorkspace()
        let runner = VerificationRunner(workspace: ws)
        let human = VerificationCheck.human(category: "ux", instruction: "click around")
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor, verifications: [human])
        try ws.tasks.save(task)

        let updated = try runner.runAutomated(taskId: task.id)
        #expect(updated.verifications.first?.status == .pending)
    }

    @Test func recordHumanResult_marksPassed() throws {
        let ws = try makeWorkspace()
        let runner = VerificationRunner(workspace: ws)
        let human = VerificationCheck.human(category: "ux", instruction: "x")
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor, verifications: [human])
        try ws.tasks.save(task)

        let updated = try runner.recordHumanResult(
            taskId: task.id, checkId: human.id, passed: true, evidence: "looked OK"
        )
        #expect(updated.verifications.first?.status == .passed)
    }

    @Test func waive_marksWaived() throws {
        let ws = try makeWorkspace()
        let runner = VerificationRunner(workspace: ws)
        let human = VerificationCheck.human(category: "ux", instruction: "x")
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor, verifications: [human])
        try ws.tasks.save(task)

        let updated = try runner.waive(
            taskId: task.id, checkId: human.id, reason: "low risk", by: approver
        )
        #expect(updated.verifications.first?.status == .waived(reason: "low risk", by: approver))
    }

    @Test func taskNotFound_throws() throws {
        let ws = try makeWorkspace()
        let runner = VerificationRunner(workspace: ws)
        #expect(throws: VerificationRunnerError.taskNotFound("nope")) {
            try runner.runAutomated(taskId: "nope")
        }
    }
}
