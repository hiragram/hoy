import Foundation
import SQLite

public final class IntentRepository {
    private let storage: SQLiteStorage

    public init(storage: SQLiteStorage) {
        self.storage = storage
    }

    public func save(_ intent: Intent) throws {
        let (statusStr, closedReason): (String, String?) = {
            switch intent.status {
            case .active: return ("active", nil)
            case .closed(let reason): return ("closed", reason)
            }
        }()
        try storage.db.run(
            """
            INSERT OR REPLACE INTO intents
            (id, version, title, body, status, closed_reason, parent_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            intent.id,
            intent.version,
            intent.title,
            intent.body,
            statusStr,
            closedReason,
            intent.parentId
        )
    }

    public func latest(id: String) throws -> Intent? {
        let stmt = try storage.db.prepare(
            """
            SELECT id, version, title, body, status, closed_reason, parent_id
            FROM intents
            WHERE id = ?
            ORDER BY version DESC
            LIMIT 1
            """,
            id
        )
        for row in stmt {
            return try decode(row: row)
        }
        return nil
    }

    private func decode(row: Statement.Element) throws -> Intent {
        let id = row[0] as! String
        let version = Int(row[1] as! Int64)
        let title = row[2] as! String
        let body = row[3] as! String
        let statusStr = row[4] as! String
        let closedReason = row[5] as? String
        let parentId = row[6] as? String

        let status: Intent.Status
        switch statusStr {
        case "active":
            status = .active
        case "closed":
            status = .closed(reason: closedReason ?? "")
        default:
            throw IntentRepositoryError.invalidStatus(statusStr)
        }
        return Intent(
            id: id,
            version: version,
            title: title,
            body: body,
            status: status,
            parentId: parentId
        )
    }
}

public enum IntentRepositoryError: Error, Equatable {
    case invalidStatus(String)
}
