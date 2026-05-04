import Foundation
import SQLite

public enum PrincipalRepositoryError: Error, Equatable {
    case invalidKind(String)
}

public final class PrincipalRepository {
    private let storage: SQLiteStorage

    public init(storage: SQLiteStorage) {
        self.storage = storage
    }

    public func save(_ principal: Principal) throws {
        try storage.db.run(
            """
            INSERT OR REPLACE INTO principals (id, kind, display_name, created_at)
            VALUES (?, ?, ?, ?)
            """,
            principal.id,
            principal.kind.rawValue,
            principal.displayName,
            principal.createdAt.timeIntervalSince1970
        )
    }

    public func get(id: String) throws -> Principal? {
        let stmt = try storage.db.prepare(
            "SELECT id, kind, display_name, created_at FROM principals WHERE id = ?",
            id
        )
        for row in stmt {
            let pid = row[0] as! String
            let kindStr = row[1] as! String
            let name = row[2] as! String
            let createdAt = row[3] as! Double
            guard let kind = PrincipalRef.Kind(rawValue: kindStr) else {
                throw PrincipalRepositoryError.invalidKind(kindStr)
            }
            return Principal(
                id: pid,
                kind: kind,
                displayName: name,
                createdAt: Date(timeIntervalSince1970: createdAt)
            )
        }
        return nil
    }
}
