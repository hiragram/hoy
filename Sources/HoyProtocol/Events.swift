import Foundation

// ADR 0016: daemon → クライアント / agent への通知イベント。
// JSON-RPC 2.0 の notification (id なし) として送る想定。

public enum EventName {
    public static let taskCompleted = "task.completed"
    public static let taskReverted = "task.reverted"
    public static let verificationFailed = "verification.failed"
    public static let claimExpired = "claim.expired"
    public static let conflictDetected = "conflict.detected"
}

public struct EventEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: Payload

    public init(method: String, params: Payload) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

public struct TaskCompletedEvent: Codable, Sendable, Equatable {
    public let taskId: String
    public let intentId: String
    public let sha: String
    public init(taskId: String, intentId: String, sha: String) {
        self.taskId = taskId; self.intentId = intentId; self.sha = sha
    }
}

public struct VerificationFailedEvent: Codable, Sendable, Equatable {
    public let taskId: String
    public let checkId: String
    public let category: String
    public init(taskId: String, checkId: String, category: String) {
        self.taskId = taskId; self.checkId = checkId; self.category = category
    }
}

public struct ClaimExpiredEvent: Codable, Sendable, Equatable {
    public let targetIntentId: String
    public let principal: PrincipalRefDTO
    public init(targetIntentId: String, principal: PrincipalRefDTO) {
        self.targetIntentId = targetIntentId
        self.principal = principal
    }
}
