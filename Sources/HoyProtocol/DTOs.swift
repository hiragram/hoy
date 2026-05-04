import Foundation

// HoyCore のドメイン値型を JSON で表現するための DTO。
// HoyProtocol 自体は HoyCore に依存しないため、変換は呼び出し側 (Daemon / CLI) が行う。

public struct PrincipalRefDTO: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String  // "human" | "agent"

    public init(id: String, kind: String) {
        self.id = id
        self.kind = kind
    }
}

public struct IntentRefDTO: Codable, Sendable, Equatable {
    public let id: String
    public let version: Int
    public init(id: String, version: Int) {
        self.id = id
        self.version = version
    }
}

public struct IntentDTO: Codable, Sendable, Equatable {
    public let id: String
    public let version: Int
    public let title: String
    public let body: String
    public let status: String  // "active" | "closed"
    public let closedReason: String?
    public let parentId: String?

    public init(
        id: String, version: Int, title: String, body: String,
        status: String, closedReason: String?, parentId: String?
    ) {
        self.id = id; self.version = version; self.title = title; self.body = body
        self.status = status; self.closedReason = closedReason; self.parentId = parentId
    }
}

public struct VerificationCheckDTO: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String  // "automated" | "human"
    public let category: String
    public let spec: String
    public let status: String  // "pending"|"running"|"passed"|"failed"|"waived"
    public let waivedReason: String?
    public let waivedBy: PrincipalRefDTO?
    public let evidence: String?
    public let required: Bool

    public init(
        id: String, kind: String, category: String, spec: String, status: String,
        waivedReason: String?, waivedBy: PrincipalRefDTO?, evidence: String?, required: Bool
    ) {
        self.id = id; self.kind = kind; self.category = category; self.spec = spec
        self.status = status; self.waivedReason = waivedReason; self.waivedBy = waivedBy
        self.evidence = evidence; self.required = required
    }
}

public struct TaskDTO: Codable, Sendable, Equatable {
    public let id: String
    public let intentId: String
    public let title: String
    public let createdBy: PrincipalRefDTO
    public let status: String
    public let dependsOn: [IntentRefDTO]
    public let verifications: [VerificationCheckDTO]
    public let completedSha: String?

    public init(
        id: String, intentId: String, title: String, createdBy: PrincipalRefDTO,
        status: String, dependsOn: [IntentRefDTO],
        verifications: [VerificationCheckDTO], completedSha: String?
    ) {
        self.id = id; self.intentId = intentId; self.title = title
        self.createdBy = createdBy; self.status = status
        self.dependsOn = dependsOn; self.verifications = verifications
        self.completedSha = completedSha
    }
}

public struct ClaimDTO: Codable, Sendable, Equatable {
    public let principal: PrincipalRefDTO
    public let targetIntentId: String
    public let acquiredAt: Double  // unix epoch seconds
    public let expiresAt: Double

    public init(
        principal: PrincipalRefDTO, targetIntentId: String,
        acquiredAt: Double, expiresAt: Double
    ) {
        self.principal = principal; self.targetIntentId = targetIntentId
        self.acquiredAt = acquiredAt; self.expiresAt = expiresAt
    }
}
