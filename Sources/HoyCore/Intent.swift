import Foundation

public struct Intent {
    public enum Status: Equatable {
        case active
        case closed(reason: String)
    }

    public let id: String
    public let version: Int
    public let title: String
    public let body: String
    public let status: Status
    public let parentId: String?

    public static func create(
        title: String,
        body: String = "",
        parentId: String? = nil
    ) -> Intent {
        return Intent(
            id: UUID().uuidString,
            version: 1,
            title: title,
            body: body,
            status: .active,
            parentId: parentId
        )
    }
}
