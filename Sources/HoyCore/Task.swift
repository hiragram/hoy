import Foundation

public enum HoyTaskError: Error, Equatable {
    case invalidTransition
    case verificationsNotSatisfied
}

// Swift 並行性の `Task` と衝突するので `HoyTask` で定義する。
public struct HoyTask: Equatable {
    public enum Status: String, Equatable, Hashable {
        case open
        case claimed
        case inProgress
        case completed
        case reverted
        case closed
    }

    public let id: String
    public let intentId: String
    public let title: String
    public let createdBy: PrincipalRef
    public let status: Status
    public let dependsOn: [IntentRef]
    public let verifications: [VerificationCheck]
    public let completedSha: String?

    public static func create(
        intentId: String,
        title: String,
        createdBy: PrincipalRef,
        dependsOn: [IntentRef] = [],
        verifications: [VerificationCheck] = []
    ) -> HoyTask {
        return HoyTask(
            id: UUID().uuidString,
            intentId: intentId,
            title: title,
            createdBy: createdBy,
            status: .open,
            dependsOn: dependsOn,
            verifications: verifications,
            completedSha: nil
        )
    }

    public func complete(sha: String?) throws -> HoyTask {
        guard status != .completed else { throw HoyTaskError.invalidTransition }
        guard VerificationGate.allRequiredSatisfied(in: verifications) else {
            throw HoyTaskError.verificationsNotSatisfied
        }
        return with(status: .completed, completedSha: sha)
    }

    /// 「やらない」「他で済んだ」など完了でも revert でもなく Task を畳む。
    public func close() throws -> HoyTask {
        switch status {
        case .closed, .reverted:
            throw HoyTaskError.invalidTransition
        case .open, .claimed, .inProgress, .completed:
            return with(status: .closed, completedSha: completedSha)
        }
    }

    public func revert() throws -> HoyTask {
        guard status == .completed else { throw HoyTaskError.invalidTransition }
        return with(status: .reverted, completedSha: completedSha)
    }

    /// ADR 0024: Intent close 時の cascade close。任意の状態から closed に遷移可能。
    public func cascadeClose() -> HoyTask {
        return with(status: .closed, completedSha: completedSha)
    }

    private func with(status: Status, completedSha: String?) -> HoyTask {
        return HoyTask(
            id: id,
            intentId: intentId,
            title: title,
            createdBy: createdBy,
            status: status,
            dependsOn: dependsOn,
            verifications: verifications,
            completedSha: completedSha
        )
    }
}
