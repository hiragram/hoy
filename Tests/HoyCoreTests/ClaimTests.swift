import Testing
import Foundation
@testable import HoyCore

struct ClaimTests {
    private let principal = PrincipalRef(id: "agent-1", kind: .agent)

    @Test func acquire_recordsPrincipalAndTarget() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let claim = Claim.acquire(
            principal: principal,
            targetIntentId: "intent-1",
            now: now,
            ttl: 60
        )
        #expect(claim.principal == principal)
        #expect(claim.targetIntentId == "intent-1")
        #expect(claim.acquiredAt == now)
        #expect(claim.expiresAt == now.addingTimeInterval(60))
    }

    // ADR 0011: 期限切れ判定
    @Test func isExpired_beforeExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let claim = Claim.acquire(principal: principal, targetIntentId: "i", now: now, ttl: 60)
        #expect(!claim.isExpired(at: now.addingTimeInterval(30)))
    }

    @Test func isExpired_afterExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let claim = Claim.acquire(principal: principal, targetIntentId: "i", now: now, ttl: 60)
        #expect(claim.isExpired(at: now.addingTimeInterval(61)))
    }

    // ADR 0011: ハートビートで expiresAt を延長
    @Test func heartbeat_extendsExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let claim = Claim.acquire(principal: principal, targetIntentId: "i", now: now, ttl: 60)
        let later = now.addingTimeInterval(30)
        let renewed = claim.heartbeat(at: later, ttl: 60)
        #expect(renewed.expiresAt == later.addingTimeInterval(60))
        #expect(renewed.principal == claim.principal)
        #expect(renewed.targetIntentId == claim.targetIntentId)
    }
}
