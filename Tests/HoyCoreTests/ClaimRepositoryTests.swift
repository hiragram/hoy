import Testing
import Foundation
@testable import HoyCore

struct ClaimRepositoryTests {
    private let agentA = PrincipalRef(id: "agent-a", kind: .agent)
    private let agentB = PrincipalRef(id: "agent-b", kind: .agent)

    private func makeRepo() throws -> ClaimRepository {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-\(UUID().uuidString).sqlite")
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        return ClaimRepository(storage: storage)
    }

    @Test func acquire_storesClaim() throws {
        let repo = try makeRepo()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let claim = Claim.acquire(principal: agentA, targetIntentId: "i-1", now: now, ttl: 60)
        try repo.acquire(claim, now: now)
        let loaded = try repo.get(targetIntentId: "i-1")
        #expect(loaded == claim)
    }

    // ADR 0009: 同一 Intent への 2 Principal の同時 claim を拒否
    @Test func acquire_rejectsConflict() throws {
        let repo = try makeRepo()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let a = Claim.acquire(principal: agentA, targetIntentId: "i-1", now: now, ttl: 60)
        try repo.acquire(a, now: now)

        let b = Claim.acquire(principal: agentB, targetIntentId: "i-1", now: now, ttl: 60)
        #expect {
            try repo.acquire(b, now: now)
        } throws: { error in
            guard case ClaimRepositoryError.alreadyClaimed(let by) = error else { return false }
            return by == self.agentA
        }
    }

    // ADR 0011: 期限切れ claim は奪える
    @Test func acquire_takesOverExpiredClaim() throws {
        let repo = try makeRepo()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let a = Claim.acquire(principal: agentA, targetIntentId: "i-1", now: start, ttl: 60)
        try repo.acquire(a, now: start)

        let later = start.addingTimeInterval(120)
        let b = Claim.acquire(principal: agentB, targetIntentId: "i-1", now: later, ttl: 60)
        try repo.acquire(b, now: later)
        let loaded = try repo.get(targetIntentId: "i-1")
        #expect(loaded?.principal == agentB)
    }

    @Test func release_removesClaim() throws {
        let repo = try makeRepo()
        let now = Date()
        let claim = Claim.acquire(principal: agentA, targetIntentId: "i-1", now: now, ttl: 60)
        try repo.acquire(claim, now: now)
        try repo.release(targetIntentId: "i-1", by: agentA)
        #expect(try repo.get(targetIntentId: "i-1") == nil)
    }

    @Test func heartbeat_extendsExpiry() throws {
        let repo = try makeRepo()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let claim = Claim.acquire(principal: agentA, targetIntentId: "i-1", now: start, ttl: 60)
        try repo.acquire(claim, now: start)

        let later = start.addingTimeInterval(30)
        try repo.heartbeat(targetIntentId: "i-1", by: agentA, now: later, ttl: 60)
        let loaded = try repo.get(targetIntentId: "i-1")
        #expect(loaded?.expiresAt == later.addingTimeInterval(60))
    }
}

struct PrincipalRepositoryTests {
    private func makeRepo() throws -> PrincipalRepository {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-\(UUID().uuidString).sqlite")
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        return PrincipalRepository(storage: storage)
    }

    @Test func roundTrip() throws {
        let repo = try makeRepo()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = Principal.create(kind: .human, displayName: "yuya", now: now)
        try repo.save(p)
        let loaded = try repo.get(id: p.id)
        #expect(loaded == p)
    }
}

struct SessionRepositoryTests {
    private func makeRepo() throws -> (SessionRepository, PrincipalRepository) {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-\(UUID().uuidString).sqlite")
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        return (SessionRepository(storage: storage), PrincipalRepository(storage: storage))
    }

    @Test func roundTripAndFindByToken() throws {
        let (sessions, principals) = try makeRepo()
        let p = Principal.create(kind: .agent, displayName: "claude", now: Date())
        try principals.save(p)
        let s = Session.start(for: p, now: Date(timeIntervalSince1970: 1_000_000))
        try sessions.save(s)
        #expect(try sessions.get(id: s.id) == s)
        #expect(try sessions.findByToken(s.token) == s)
    }
}

struct AuditLogRepositoryTests {
    private let actor = PrincipalRef(id: "agent-1", kind: .agent)

    private func makeRepo() throws -> AuditLogRepository {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-\(UUID().uuidString).sqlite")
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        return AuditLogRepository(storage: storage)
    }

    @Test func append_thenAll() throws {
        let repo = try makeRepo()
        let e1 = AuditEntry.record(
            actor: actor, op: "intent.create", payload: ["id": "i-1"],
            now: Date(timeIntervalSince1970: 1)
        )
        let e2 = AuditEntry.record(
            actor: actor, op: "task.complete", payload: ["id": "t-1"],
            now: Date(timeIntervalSince1970: 2)
        )
        try repo.append(e1)
        try repo.append(e2)
        let all = try repo.all()
        #expect(all.count == 2)
        #expect(all[0].op == "intent.create")
        #expect(all[1].op == "task.complete")
    }

    // ADR 0027: append-only — UPDATE/DELETE はトリガーで拒否
    @Test func update_isRejectedByTrigger() throws {
        let repo = try makeRepo()
        let e = AuditEntry.record(
            actor: actor, op: "x", payload: [:], now: Date()
        )
        try repo.append(e)

        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-\(UUID().uuidString).sqlite")
        // 既存接続を直接叩く: 同じテストの SQLiteStorage を取得できるよう取り直す方が綺麗だが、
        // ここは repo.storage 経由を増やさず、新規 repo 経由で UPDATE を試みる
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        let r2 = AuditLogRepository(storage: storage)
        try r2.append(e)
        var threw = false
        do {
            try storage.db.run("UPDATE audit_log SET op = 'evil'")
        } catch {
            threw = true
        }
        #expect(threw)
    }
}
