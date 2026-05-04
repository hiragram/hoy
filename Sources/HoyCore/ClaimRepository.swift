import Foundation
import SQLite

public enum ClaimRepositoryError: Error, Equatable {
    case alreadyClaimed(by: PrincipalRef)
    case invalidPrincipalKind(String)
}

// ADR 0009: Intent 単位で 1 Principal が排他。本リポジトリは
// target_intent_id を主キーとしてその不変条件を保つ。
public final class ClaimRepository {
    private let storage: SQLiteStorage

    public init(storage: SQLiteStorage) {
        self.storage = storage
    }

    /// claim を取得する。同一 Intent に対する有効な claim が他 Principal に
    /// あれば `alreadyClaimed` を返す。期限切れの claim は奪える。
    public func acquire(_ claim: Claim, now: Date) throws {
        try storage.db.transaction {
            if let existing = try self.get(targetIntentId: claim.targetIntentId) {
                if !existing.isExpired(at: now) && existing.principal != claim.principal {
                    throw ClaimRepositoryError.alreadyClaimed(by: existing.principal)
                }
            }
            try self.upsert(claim)
        }
    }

    public func heartbeat(targetIntentId: String, by principal: PrincipalRef, now: Date, ttl: TimeInterval) throws {
        guard let existing = try get(targetIntentId: targetIntentId),
              existing.principal == principal else {
            return
        }
        try upsert(existing.heartbeat(at: now, ttl: ttl))
    }

    public func release(targetIntentId: String, by principal: PrincipalRef) throws {
        try storage.db.run(
            "DELETE FROM claims WHERE target_intent_id = ? AND principal_id = ?",
            targetIntentId, principal.id
        )
    }

    public func get(targetIntentId: String) throws -> Claim? {
        let stmt = try storage.db.prepare(
            """
            SELECT principal_id, principal_kind, acquired_at, expires_at
            FROM claims WHERE target_intent_id = ?
            """,
            targetIntentId
        )
        for row in stmt {
            let id = row[0] as! String
            let kindStr = row[1] as! String
            let acquired = row[2] as! Double
            let expires = row[3] as! Double
            guard let kind = PrincipalRef.Kind(rawValue: kindStr) else {
                throw ClaimRepositoryError.invalidPrincipalKind(kindStr)
            }
            return Claim(
                principal: PrincipalRef(id: id, kind: kind),
                targetIntentId: targetIntentId,
                acquiredAt: Date(timeIntervalSince1970: acquired),
                expiresAt: Date(timeIntervalSince1970: expires)
            )
        }
        return nil
    }

    private func upsert(_ claim: Claim) throws {
        try storage.db.run(
            """
            INSERT OR REPLACE INTO claims
            (target_intent_id, principal_id, principal_kind, acquired_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            claim.targetIntentId,
            claim.principal.id,
            claim.principal.kind.rawValue,
            claim.acquiredAt.timeIntervalSince1970,
            claim.expiresAt.timeIntervalSince1970
        )
    }
}
