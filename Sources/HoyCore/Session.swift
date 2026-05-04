import Foundation

// ADR 0025: 1 Principal が複数 Session を持てる。
// token は Session ごとに一意。ストレージ層ではハッシュ保管が想定だが、値型レベルでは平文を保持する。
public struct Session: Equatable {
    public let id: String
    public let principalId: String
    public let token: String
    public let createdAt: Date
    public let lastSeenAt: Date

    public static func start(for principal: Principal, now: Date) -> Session {
        return Session(
            id: UUID().uuidString,
            principalId: principal.id,
            token: generateToken(),
            createdAt: now,
            lastSeenAt: now
        )
    }

    public func touch(at now: Date) -> Session {
        return Session(
            id: id,
            principalId: principalId,
            token: token,
            createdAt: createdAt,
            lastSeenAt: now
        )
    }

    private static func generateToken() -> String {
        // 32 byte の乱数を hex 化
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<bytes.count {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
