import Foundation

public enum VerificationCheckError: Error, Equatable {
    case invalidTransition
}

public struct VerificationCheck: Equatable {
    public enum Kind: Equatable {
        case automated(command: String)
        case human(instruction: String)
    }

    public enum Status: Equatable {
        case pending
        case running
        case passed
        case failed
        case waived(reason: String, by: PrincipalRef)
    }

    public let id: String
    public let kind: Kind
    public let category: String
    public let status: Status
    public let required: Bool
    public let evidence: String?
    /// ADR 0048 Stage 2: この check は「pass の前に fail を観察した履歴」が
    /// あって初めて gate を満たす(test-first 強制)。
    public let testFirst: Bool
    /// pass/waive 判定で参照される。markFailed のたびに true になり、
    /// resetToPending で false に戻る。
    public let redObserved: Bool

    public static func automated(
        category: String,
        command: String,
        required: Bool = true,
        testFirst: Bool = false
    ) -> VerificationCheck {
        return VerificationCheck(
            id: UUID().uuidString,
            kind: .automated(command: command),
            category: category,
            status: .pending,
            required: required,
            evidence: nil,
            testFirst: testFirst,
            redObserved: false
        )
    }

    public static func human(
        category: String,
        instruction: String,
        required: Bool = true,
        testFirst: Bool = false
    ) -> VerificationCheck {
        return VerificationCheck(
            id: UUID().uuidString,
            kind: .human(instruction: instruction),
            category: category,
            status: .pending,
            required: required,
            evidence: nil,
            testFirst: testFirst,
            redObserved: false
        )
    }

    public func markPassed(evidence: String) throws -> VerificationCheck {
        try requireNotTerminal()
        return with(status: .passed, evidence: evidence, redObserved: redObserved)
    }

    public func markFailed(evidence: String) throws -> VerificationCheck {
        try requireNotTerminal()
        return with(status: .failed, evidence: evidence, redObserved: true)
    }

    public func waive(reason: String, by approver: PrincipalRef) throws -> VerificationCheck {
        if case .waived = status {
            throw VerificationCheckError.invalidTransition
        }
        return with(
            status: .waived(reason: reason, by: approver),
            evidence: evidence,
            redObserved: redObserved
        )
    }

    /// 統合後の再走 (ADR 0017) などで、terminal 状態の automated check を
    /// pending に戻す。redObserved もリセット(統合により世界線が更新された)。
    public func resetToPending() -> VerificationCheck {
        switch (kind, status) {
        case (.automated, .passed), (.automated, .failed):
            return with(status: .pending, evidence: nil, redObserved: false)
        default:
            return self
        }
    }

    /// 同一 task 内で fail 後に再 run する用。redObserved を保持しつつ
    /// pending に戻す(これにより markPassed/markFailed が呼べる)。
    public func prepareForRerun() -> VerificationCheck {
        if case .failed = status {
            return with(status: .pending, evidence: nil, redObserved: redObserved)
        }
        return self
    }

    private func requireNotTerminal() throws {
        switch status {
        case .pending, .running:
            return
        case .passed, .failed, .waived:
            throw VerificationCheckError.invalidTransition
        }
    }

    private func with(status: Status, evidence: String?, redObserved: Bool) -> VerificationCheck {
        return VerificationCheck(
            id: id,
            kind: kind,
            category: category,
            status: status,
            required: required,
            evidence: evidence,
            testFirst: testFirst,
            redObserved: redObserved
        )
    }
}

public enum VerificationGate {
    /// 必須 check がすべて satisfied か。
    /// satisfied = waived OR (passed AND (testFirst が無い OR redObserved を観察済))
    public static func allRequiredSatisfied(in checks: [VerificationCheck]) -> Bool {
        for check in checks where check.required {
            switch check.status {
            case .waived:
                continue
            case .passed:
                if check.testFirst && !check.redObserved {
                    return false
                }
                continue
            default:
                return false
            }
        }
        return true
    }
}
