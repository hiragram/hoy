import Foundation

public enum IntentError: Error, Equatable {
    case alreadyClosed
}

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

    public func update(title: String? = nil, body: String? = nil) -> Intent {
        return Intent(
            id: id,
            version: version + 1,
            title: title ?? self.title,
            body: body ?? self.body,
            status: status,
            parentId: parentId
        )
    }

    public func close(reason: String) throws -> Intent {
        if case .closed = status {
            throw IntentError.alreadyClosed
        }
        return Intent(
            id: id,
            version: version + 1,
            title: title,
            body: body,
            status: .closed(reason: reason),
            parentId: parentId
        )
    }
}
