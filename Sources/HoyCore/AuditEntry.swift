import Foundation

// ADR 0027: 全状態変更操作を append-only ストリームに記録する。
// 値型としては不変(全プロパティ let)。書き換え操作は提供しない。
public struct AuditEntry: Equatable {
    public let id: String
    public let timestamp: Date
    public let actor: PrincipalRef
    public let op: String
    public let payload: [String: String]

    public static func record(
        actor: PrincipalRef,
        op: String,
        payload: [String: String],
        now: Date
    ) -> AuditEntry {
        return AuditEntry(
            id: UUID().uuidString,
            timestamp: now,
            actor: actor,
            op: op,
            payload: payload
        )
    }
}
