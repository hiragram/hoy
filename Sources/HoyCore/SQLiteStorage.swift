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
        """,
        // v3: tasks, task_dependencies, verifications
        """
        CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            intent_id TEXT NOT NULL,
            title TEXT NOT NULL,
            created_by_id TEXT NOT NULL,
            created_by_kind TEXT NOT NULL,
            status TEXT NOT NULL
        );
        CREATE INDEX idx_tasks_intent ON tasks(intent_id);

        CREATE TABLE task_dependencies (
            task_id TEXT NOT NULL,
            intent_id TEXT NOT NULL,
            intent_version INTEGER NOT NULL,
            PRIMARY KEY (task_id, intent_id, intent_version),
            FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
        );

        CREATE TABLE verifications (
            id TEXT PRIMARY KEY,
            task_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            category TEXT NOT NULL,
            spec TEXT NOT NULL,
            status TEXT NOT NULL,
            waived_reason TEXT,
            waived_by_id TEXT,
            waived_by_kind TEXT,
            evidence TEXT,
            required INTEGER NOT NULL,
            ordering INTEGER NOT NULL,
            FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
        );
        CREATE INDEX idx_verifications_task ON verifications(task_id);
        """,
        // v4: claims, principals, sessions
        """
        CREATE TABLE claims (
            target_intent_id TEXT PRIMARY KEY,
            principal_id TEXT NOT NULL,
            principal_kind TEXT NOT NULL,
            acquired_at REAL NOT NULL,
            expires_at REAL NOT NULL
        );

        CREATE TABLE principals (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            display_name TEXT NOT NULL,
            created_at REAL NOT NULL
        );

        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            principal_id TEXT NOT NULL,
            token TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            FOREIGN KEY (principal_id) REFERENCES principals(id)
        );
        CREATE INDEX idx_sessions_principal ON sessions(principal_id);
        """,
        // v5: audit_log with append-only triggers (ADR 0027)
        """
        CREATE TABLE audit_log (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            actor_id TEXT NOT NULL,
            actor_kind TEXT NOT NULL,
            op TEXT NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE INDEX idx_audit_log_ts ON audit_log(timestamp);

        CREATE TRIGGER audit_log_no_update BEFORE UPDATE ON audit_log
        BEGIN
            SELECT RAISE(ABORT, 'audit_log is append-only');
        END;
        CREATE TRIGGER audit_log_no_delete BEFORE DELETE ON audit_log
        BEGIN
            SELECT RAISE(ABORT, 'audit_log is append-only');
        END;
        """,
        // v6: tasks に completed_sha 列を追加
        """
        ALTER TABLE tasks ADD COLUMN completed_sha TEXT;
        """,
        // v7: verifications に test_first / red_observed 列を追加 (ADR 0048 Stage 2)
        """
        ALTER TABLE verifications ADD COLUMN test_first INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE verifications ADD COLUMN red_observed INTEGER NOT NULL DEFAULT 0;
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

    /// WAL を本体ファイルに取り込む。task.complete のような mutation の後に
    /// 呼んで永続性ウィンドウを縮める用途。失敗は致命でないので呼出側で握り潰してよい。
    public func checkpoint() throws {
        try db.run("PRAGMA wal_checkpoint(PASSIVE)")
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
