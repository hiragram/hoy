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

    public static func automated(
        category: String,
        command: String,
        required: Bool = true
    ) -> VerificationCheck {
        return VerificationCheck(
            id: UUID().uuidString,
            kind: .automated(command: command),
            category: category,
            status: .pending,
            required: required,
            evidence: nil
        )
    }

    public static func human(
        category: String,
        instruction: String,
        required: Bool = true
    ) -> VerificationCheck {
        return VerificationCheck(
            id: UUID().uuidString,
            kind: .human(instruction: instruction),
            category: category,
            status: .pending,
            required: required,
            evidence: nil
        )
    }

    public func markPassed(evidence: String) throws -> VerificationCheck {
        try requireNotTerminal()
        return with(status: .passed, evidence: evidence)
    }

    public func markFailed(evidence: String) throws -> VerificationCheck {
        try requireNotTerminal()
        return with(status: .failed, evidence: evidence)
    }

    public func waive(reason: String, by approver: PrincipalRef) throws -> VerificationCheck {
        try requireNotTerminal()
        return with(status: .waived(reason: reason, by: approver), evidence: evidence)
    }

    private func requireNotTerminal() throws {
        switch status {
        case .pending, .running:
            return
        case .passed, .failed, .waived:
            throw VerificationCheckError.invalidTransition
        }
    }

    private func with(status: Status, evidence: String?) -> VerificationCheck {
        return VerificationCheck(
            id: id,
            kind: kind,
            category: category,
            status: status,
            required: required,
            evidence: evidence
        )
    }
}

public enum VerificationGate {
    public static func allRequiredSatisfied(in checks: [VerificationCheck]) -> Bool {
        for check in checks where check.required {
            switch check.status {
            case .passed, .waived:
                continue
            default:
                return false
            }
        }
        return true
    }
}
