import Foundation

// ADR 0009-0012: claim は Principal 単位で確立される (書き込み排他、読み取り自由)。
// ここでは値型のみ定義。排他性の強制は ClaimRegistry (Phase 3) で扱う。
public struct Claim: Equatable {
    public let principal: PrincipalRef
    public let targetIntentId: String
    public let acquiredAt: Date
    public let expiresAt: Date

    public static func acquire(
        principal: PrincipalRef,
        targetIntentId: String,
        now: Date,
        ttl: TimeInterval
    ) -> Claim {
        return Claim(
            principal: principal,
            targetIntentId: targetIntentId,
            acquiredAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )
    }

    public func isExpired(at now: Date) -> Bool {
        return now > expiresAt
    }

    public func heartbeat(at now: Date, ttl: TimeInterval) -> Claim {
        return Claim(
            principal: principal,
            targetIntentId: targetIntentId,
            acquiredAt: acquiredAt,
            expiresAt: now.addingTimeInterval(ttl)
        )
    }
}
