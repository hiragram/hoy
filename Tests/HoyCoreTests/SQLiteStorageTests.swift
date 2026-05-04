import Testing
import Foundation
@testable import HoyCore

struct SQLiteStorageTests {
    private func tempPath(_ name: String = "hoy-\(UUID().uuidString).sqlite") -> String {
        let dir = NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent(name)
    }

    @Test func open_createsDatabaseFile() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try SQLiteStorage.open(at: path)
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func migrate_setsSchemaVersion() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        #expect(try storage.schemaVersion() == storage.latestSchemaVersion)
    }

    @Test func migrate_isIdempotent() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let storage = try SQLiteStorage.open(at: path)
        try storage.migrate()
        try storage.migrate()
        #expect(try storage.schemaVersion() == storage.latestSchemaVersion)
    }

    @Test func reopen_preservesSchemaVersion() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let storage = try SQLiteStorage.open(at: path)
            try storage.migrate()
        }
        let storage = try SQLiteStorage.open(at: path)
        #expect(try storage.schemaVersion() == storage.latestSchemaVersion)
    }
}
