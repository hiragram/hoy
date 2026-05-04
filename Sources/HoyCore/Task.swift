import Foundation

public enum HoyTaskError: Error, Equatable {
    case invalidTransition
}

// Swift 並行性の `Task` と衝突するので `HoyTask` で定義する。
public struct HoyTask {
    public enum Status: String, Equatable {
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

    public static func create(
        intentId: String,
        title: String,
        createdBy: PrincipalRef,
        dependsOn: [IntentRef] = []
    ) -> HoyTask {
        return HoyTask(
            id: UUID().uuidString,
            intentId: intentId,
            title: title,
            createdBy: createdBy,
            status: .open,
            dependsOn: dependsOn
        )
    }

    public func complete() throws -> HoyTask {
        guard status != .completed else { throw HoyTaskError.invalidTransition }
        return with(status: .completed)
    }

    public func revert() throws -> HoyTask {
        guard status == .completed else { throw HoyTaskError.invalidTransition }
        return with(status: .reverted)
    }

    private func with(status: Status) -> HoyTask {
        return HoyTask(
            id: id,
            intentId: intentId,
            title: title,
            createdBy: createdBy,
            status: status,
            dependsOn: dependsOn
        )
    }
}
