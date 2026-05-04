import Testing
import Foundation
@testable import HoyCore

struct AuditEntryTests {
    private let actor = PrincipalRef(id: "agent-1", kind: .agent)

    @Test func record_assignsIdAndPreservesFields() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let entry = AuditEntry.record(
            actor: actor,
            op: "intent.create",
            payload: ["intentId": "i-1"],
            now: now
        )
        #expect(!entry.id.isEmpty)
        #expect(entry.timestamp == now)
        #expect(entry.actor == actor)
        #expect(entry.op == "intent.create")
        #expect(entry.payload == ["intentId": "i-1"])
    }

    @Test func record_uniqueIds() {
        let now = Date()
        let a = AuditEntry.record(actor: actor, op: "x", payload: [:], now: now)
        let b = AuditEntry.record(actor: actor, op: "x", payload: [:], now: now)
        #expect(a.id != b.id)
    }
}
