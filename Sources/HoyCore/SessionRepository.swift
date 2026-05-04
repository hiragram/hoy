import Foundation
import SQLite

public final class SessionRepository {
    private let storage: SQLiteStorage

    public init(storage: SQLiteStorage) {
        self.storage = storage
    }

    public func save(_ session: Session) throws {
        try storage.db.run(
            """
            INSERT OR REPLACE INTO sessions
            (id, principal_id, token, created_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            session.id,
            session.principalId,
            session.token,
            session.createdAt.timeIntervalSince1970,
            session.lastSeenAt.timeIntervalSince1970
        )
    }

    public func get(id: String) throws -> Session? {
        let stmt = try storage.db.prepare(
            "SELECT id, principal_id, token, created_at, last_seen_at FROM sessions WHERE id = ?",
            id
        )
        return try mapSingle(stmt: stmt)
    }

    public func findByToken(_ token: String) throws -> Session? {
        let stmt = try storage.db.prepare(
            "SELECT id, principal_id, token, created_at, last_seen_at FROM sessions WHERE token = ?",
            token
        )
        return try mapSingle(stmt: stmt)
    }

    private func mapSingle(stmt: Statement) throws -> Session? {
        for row in stmt {
            return Session(
                id: row[0] as! String,
                principalId: row[1] as! String,
                token: row[2] as! String,
                createdAt: Date(timeIntervalSince1970: row[3] as! Double),
                lastSeenAt: Date(timeIntervalSince1970: row[4] as! Double)
            )
        }
        return nil
    }
}
