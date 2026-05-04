import Testing
import Foundation
@testable import HoyCore

struct PrincipalTests {
    @Test func create_assignsIdAndPreservesFields() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = Principal.create(kind: .agent, displayName: "claude", now: now)
        #expect(!p.id.isEmpty)
        #expect(p.kind == .agent)
        #expect(p.displayName == "claude")
        #expect(p.createdAt == now)
    }

    @Test func ref_returnsMatchingRef() {
        let p = Principal.create(kind: .human, displayName: "yuya", now: Date())
        let ref = p.ref
        #expect(ref.id == p.id)
        #expect(ref.kind == p.kind)
    }
}

struct SessionTests {
    private let principal = Principal.create(
        kind: .human,
        displayName: "u",
        now: Date(timeIntervalSince1970: 0)
    )

    @Test func start_generatesUniqueIdAndToken() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let a = Session.start(for: principal, now: now)
        let b = Session.start(for: principal, now: now)
        #expect(a.id != b.id)
        #expect(a.token != b.token)
        #expect(!a.token.isEmpty)
    }

    @Test func start_recordsPrincipalAndTimestamps() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = Session.start(for: principal, now: now)
        #expect(s.principalId == principal.id)
        #expect(s.createdAt == now)
        #expect(s.lastSeenAt == now)
    }

    @Test func touch_updatesLastSeen() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let s = Session.start(for: principal, now: start)
        let later = start.addingTimeInterval(120)
        let touched = s.touch(at: later)
        #expect(touched.lastSeenAt == later)
        #expect(touched.id == s.id)
        #expect(touched.token == s.token)
        #expect(touched.createdAt == s.createdAt)
    }
}
