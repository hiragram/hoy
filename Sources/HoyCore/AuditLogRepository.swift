import Foundation
import SQLite

public enum AuditLogRepositoryError: Error, Equatable {
    case invalidActorKind(String)
}

// ADR 0027: append-only。SQL トリガーで UPDATE/DELETE を拒否するため、
// 本リポジトリは append のみ提供する。読み取りは MVP 段階では grep 等で行う想定。
public final class AuditLogRepository {
    private let storage: SQLiteStorage

    public init(storage: SQLiteStorage) {
        self.storage = storage
    }

    public func append(_ entry: AuditEntry) throws {
        try storage.db.run(
            """
            INSERT INTO audit_log (id, timestamp, actor_id, actor_kind, op, payload)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            entry.id,
            entry.timestamp.timeIntervalSince1970,
            entry.actor.id,
            entry.actor.kind.rawValue,
            entry.op,
            try Self.encodePayload(entry.payload)
        )
    }

    /// 最新 N 件を新しい順で返す (timestamp DESC)。ダッシュボードの活動 feed 用。
    public func tail(limit: Int) throws -> [AuditEntry] {
        let stmt = try storage.db.prepare(
            """
            SELECT id, timestamp, actor_id, actor_kind, op, payload FROM audit_log
            ORDER BY timestamp DESC LIMIT ?
            """,
            limit
        )
        var out: [AuditEntry] = []
        for row in stmt {
            let id = row[0] as! String
            let ts = row[1] as! Double
            let actorId = row[2] as! String
            let actorKindStr = row[3] as! String
            let op = row[4] as! String
            let payloadStr = row[5] as! String
            guard let kind = PrincipalRef.Kind(rawValue: actorKindStr) else {
                throw AuditLogRepositoryError.invalidActorKind(actorKindStr)
            }
            out.append(AuditEntry(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                actor: PrincipalRef(id: actorId, kind: kind),
                op: op,
                payload: try Self.decodePayload(payloadStr)
            ))
        }
        return out
    }

    /// MVP 段階の最小限の読み取り。クエリ機構は ADR 0031 で MVP 外。
    public func all() throws -> [AuditEntry] {
        let stmt = try storage.db.prepare(
            "SELECT id, timestamp, actor_id, actor_kind, op, payload FROM audit_log ORDER BY timestamp ASC"
        )
        var out: [AuditEntry] = []
        for row in stmt {
            let id = row[0] as! String
            let ts = row[1] as! Double
            let actorId = row[2] as! String
            let actorKindStr = row[3] as! String
            let op = row[4] as! String
            let payloadStr = row[5] as! String
            guard let kind = PrincipalRef.Kind(rawValue: actorKindStr) else {
                throw AuditLogRepositoryError.invalidActorKind(actorKindStr)
            }
            out.append(AuditEntry(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                actor: PrincipalRef(id: actorId, kind: kind),
                op: op,
                payload: try Self.decodePayload(payloadStr)
            ))
        }
        return out
    }

    private static func encodePayload(_ payload: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decodePayload(_ raw: String) throws -> [String: String] {
        guard let data = raw.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }
}
