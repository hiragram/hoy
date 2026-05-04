import Testing
import Foundation
@testable import HoyCore

struct WorkspaceTests {
    private func makeRoot() throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-ws-\(UUID().uuidString)")
        return path
    }

    @Test func open_initializesStorageAndGit() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let ws = try Workspace.open(at: root)
        #expect(FileManager.default.fileExists(atPath: ws.storage.path))

        let dotGit = ((root as NSString).appendingPathComponent("repo") as NSString)
            .appendingPathComponent(".git")
        #expect(FileManager.default.fileExists(atPath: dotGit))
    }

    @Test func reopen_isIdempotent() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let ws1 = try Workspace.open(at: root)
        let intent = Intent.create(title: "x")
        try ws1.intents.save(intent)

        let ws2 = try Workspace.open(at: root)
        #expect(try ws2.intents.latest(id: intent.id) == intent)
    }
}

struct ClaimPurgeTests {
    private let agent = PrincipalRef(id: "a", kind: .agent)

    @Test func purgeExpired_removesOnlyExpired() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-\(UUID().uuidString).sqlite")
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        let repo = ClaimRepository(storage: storage)

        let start = Date(timeIntervalSince1970: 1_000_000)
        try repo.acquire(
            Claim.acquire(principal: agent, targetIntentId: "i-old", now: start, ttl: 60),
            now: start
        )
        let later = start.addingTimeInterval(120)
        try repo.acquire(
            Claim.acquire(principal: agent, targetIntentId: "i-fresh", now: later, ttl: 60),
            now: later
        )

        let purged = try repo.purgeExpired(now: later)
        #expect(purged == 1)
        #expect(try repo.get(targetIntentId: "i-old") == nil)
        #expect(try repo.get(targetIntentId: "i-fresh") != nil)
    }
}
