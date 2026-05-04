import Foundation

public struct Principal: Equatable {
    public let id: String
    public let kind: PrincipalRef.Kind
    public let displayName: String
    public let createdAt: Date

    public static func create(
        kind: PrincipalRef.Kind,
        displayName: String,
        now: Date
    ) -> Principal {
        return Principal(
            id: UUID().uuidString,
            kind: kind,
            displayName: displayName,
            createdAt: now
        )
    }

    public var ref: PrincipalRef {
        return PrincipalRef(id: id, kind: kind)
    }
}
