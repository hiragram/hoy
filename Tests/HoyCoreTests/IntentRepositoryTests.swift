import Testing
import Foundation
@testable import HoyCore

struct IntentRepositoryTests {
    private func makeStorage() throws -> SQLiteStorage {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-\(UUID().uuidString).sqlite")
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        return storage
    }

    @Test func save_thenGetLatestById() throws {
        let storage = try makeStorage()
        let repo = IntentRepository(storage: storage)
        let intent = Intent.create(title: "ship", body: "rationale")
        try repo.save(intent)
        let loaded = try repo.latest(id: intent.id)
        #expect(loaded == intent)
    }

    @Test func latest_returnsHighestVersion() throws {
        let storage = try makeStorage()
        let repo = IntentRepository(storage: storage)
        let v1 = Intent.create(title: "v1")
        try repo.save(v1)
        let v2 = v1.update(title: "v2")
        try repo.save(v2)
        let loaded = try repo.latest(id: v1.id)
        #expect(loaded?.version == 2)
        #expect(loaded?.title == "v2")
    }

    @Test func latest_returnsNilForUnknownId() throws {
        let storage = try makeStorage()
        let repo = IntentRepository(storage: storage)
        #expect(try repo.latest(id: "missing") == nil)
    }

    @Test func roundTrip_preservesClosedStatus() throws {
        let storage = try makeStorage()
        let repo = IntentRepository(storage: storage)
        let active = Intent.create(title: "x")
        try repo.save(active)
        let closed = try active.close(reason: "obsolete")
        try repo.save(closed)
        let loaded = try repo.latest(id: active.id)
        #expect(loaded?.status == .closed(reason: "obsolete"))
    }

    @Test func roundTrip_preservesParentId() throws {
        let storage = try makeStorage()
        let repo = IntentRepository(storage: storage)
        let intent = Intent.create(title: "child", parentId: "parent-1")
        try repo.save(intent)
        let loaded = try repo.latest(id: intent.id)
        #expect(loaded?.parentId == "parent-1")
    }

    @Test func saveSameVersion_isIdempotent() throws {
        let storage = try makeStorage()
        let repo = IntentRepository(storage: storage)
        let intent = Intent.create(title: "x")
        try repo.save(intent)
        try repo.save(intent)  // same id+version, should not throw
        let loaded = try repo.latest(id: intent.id)
        #expect(loaded == intent)
    }
}
