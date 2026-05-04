import Foundation
import SQLite

// hoy のメタデータストレージ (ADR 0038)。
// state.db を一個開き、起動時にマイグレーションを適用する。
public final class SQLiteStorage {
    public let db: Connection
    public let path: String

    private init(db: Connection, path: String) {
        self.db = db
        self.path = path
    }

    public static func open(at path: String) throws -> SQLiteStorage {
        let db = try Connection(path)
        // WAL で並行性を確保 (ADR 0038)
        try db.run("PRAGMA journal_mode = WAL")
        try db.run("PRAGMA foreign_keys = ON")
        return SQLiteStorage(db: db, path: path)
    }

    // 適用すべきマイグレーション一覧。version = 配列インデックス + 1。
    private static let migrations: [String] = [
        // v1: schema_version table
        """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );
        """,
        // v2: intents
        """
        CREATE TABLE intents (
            id TEXT NOT NULL,
            version INTEGER NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            status TEXT NOT NULL,
            closed_reason TEXT,
            parent_id TEXT,
            PRIMARY KEY (id, version)
        );
        CREATE INDEX idx_intents_id ON intents(id);
        CREATE INDEX idx_intents_parent ON intents(parent_id);
        """
    ]

    public var latestSchemaVersion: Int { Self.migrations.count }

    public func schemaVersion() throws -> Int {
        // schema_version テーブル自体がなければ 0
        let exists = try db.scalar(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
        ) as? String
        guard exists != nil else { return 0 }
        let v = try db.scalar("SELECT COALESCE(MAX(version), 0) FROM schema_version") as? Int64
        return Int(v ?? 0)
    }

    public func migrate() throws {
        try db.transaction {
            let current = try self.schemaVersion()
            for (index, sql) in Self.migrations.enumerated() {
                let target = index + 1
                if target <= current { continue }
                try self.db.execute(sql)
                try self.db.run(
                    "INSERT INTO schema_version (version) VALUES (?)",
                    target
                )
            }
        }
    }
}
