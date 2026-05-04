import Foundation

// `<root>/auth.token` に session token を保管する。mode 0600。
public struct StoredToken: Codable, Equatable {
    public let sessionId: String
    public let token: String
    public let principalId: String
    public init(sessionId: String, token: String, principalId: String) {
        self.sessionId = sessionId; self.token = token; self.principalId = principalId
    }
}

public enum TokenStore {
    public static func path(root: String) -> String {
        return (root as NSString).appendingPathComponent("auth.token")
    }

    public static func load(root: String) -> StoredToken? {
        let p = path(root: root)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)) else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    public static func save(_ stored: StoredToken, root: String) throws {
        let data = try JSONEncoder().encode(stored)
        let p = path(root: root)
        try data.write(to: URL(fileURLWithPath: p))
        chmod(p, 0o600)
    }

    public static func clear(root: String) {
        try? FileManager.default.removeItem(atPath: path(root: root))
    }
}
