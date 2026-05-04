import Foundation

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

    public static func create(
        intentId: String,
        title: String,
        createdBy: PrincipalRef
    ) -> HoyTask {
        return HoyTask(
            id: UUID().uuidString,
            intentId: intentId,
            title: title,
            createdBy: createdBy,
            status: .open
        )
    }
}
