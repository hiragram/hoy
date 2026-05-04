import Testing
@testable import HoyCore

struct VerificationCheckTests {
    private let approver = PrincipalRef(id: "u1", kind: .human)

    @Test func automated_initialStateIsPendingAndRequired() {
        let check = VerificationCheck.automated(
            category: "unittest",
            command: "swift test"
        )
        #expect(check.status == .pending)
        #expect(check.required == true)
        #expect(check.category == "unittest")
        if case .automated(let cmd) = check.kind {
            #expect(cmd == "swift test")
        } else {
            Issue.record("expected automated kind")
        }
    }

    @Test func human_canBeNonRequired() {
        let check = VerificationCheck.human(
            category: "ux",
            instruction: "click around",
            required: false
        )
        #expect(check.required == false)
    }

    @Test func transitionToPassedRecordsEvidence() throws {
        let check = VerificationCheck.automated(category: "unittest", command: "swift test")
        let passed = try check.markPassed(evidence: "exit 0")
        #expect(passed.status == .passed)
        #expect(passed.evidence == "exit 0")
    }

    @Test func transitionToFailedRecordsEvidence() throws {
        let check = VerificationCheck.automated(category: "unittest", command: "swift test")
        let failed = try check.markFailed(evidence: "exit 1\nstderr...")
        #expect(failed.status == .failed)
    }

    // concept §5.4: waived は reason と by が必須
    @Test func waiveRecordsReasonAndApprover() throws {
        let check = VerificationCheck.human(category: "ux", instruction: "manual")
        let waived = try check.waive(reason: "low risk", by: approver)
        #expect(waived.status == .waived(reason: "low risk", by: approver))
    }

    // passed からの waive は許可 (二重 waive のみ拒否)
    @Test func waiveFromPassedAllowed() throws {
        let check = VerificationCheck.automated(category: "unittest", command: "swift test")
        let passed = try check.markPassed(evidence: "ok")
        let waived = try passed.waive(reason: "drop this requirement", by: approver)
        #expect(waived.status == .waived(reason: "drop this requirement", by: approver))
    }

    @Test func waiveFromFailedAllowed() throws {
        let check = VerificationCheck.automated(category: "unittest", command: "swift test")
        let failed = try check.markFailed(evidence: "boom")
        let waived = try failed.waive(reason: "investigated, false positive", by: approver)
        #expect(waived.status == .waived(reason: "investigated, false positive", by: approver))
    }

    @Test func doubleWaiveRejected() throws {
        let check = VerificationCheck.human(category: "ux", instruction: "x")
        let waived = try check.waive(reason: "first", by: approver)
        #expect(throws: VerificationCheckError.invalidTransition) {
            try waived.waive(reason: "second", by: approver)
        }
    }
}

struct VerificationGateTests {
    private let approver = PrincipalRef(id: "u1", kind: .human)

    // concept §5.4: 必須 check が全 passed/waived なら満たす
    @Test func allRequiredPassedOrWaived_satisfied() throws {
        let a = try VerificationCheck.automated(category: "unittest", command: "x")
            .markPassed(evidence: "ok")
        let b = try VerificationCheck.human(category: "ux", instruction: "y")
            .waive(reason: "n/a", by: approver)
        #expect(VerificationGate.allRequiredSatisfied(in: [a, b]))
    }

    @Test func allRequiredPassedOrWaived_failedRequiredBlocks() throws {
        let a = try VerificationCheck.automated(category: "unittest", command: "x")
            .markFailed(evidence: "boom")
        #expect(!VerificationGate.allRequiredSatisfied(in: [a]))
    }

    @Test func allRequiredPassedOrWaived_nonRequiredFailedAllowed() throws {
        let required = try VerificationCheck.automated(category: "unittest", command: "x")
            .markPassed(evidence: "ok")
        let optional = try VerificationCheck.human(
            category: "ux",
            instruction: "y",
            required: false
        ).markFailed(evidence: "minor")
        #expect(VerificationGate.allRequiredSatisfied(in: [required, optional]))
    }

    @Test func allRequiredPassedOrWaived_pendingBlocks() {
        let pending = VerificationCheck.automated(category: "unittest", command: "x")
        #expect(!VerificationGate.allRequiredSatisfied(in: [pending]))
    }
}
