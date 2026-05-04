import Foundation
import HoyCore
import HoyProtocol

// HoyCore <-> HoyProtocol DTO の双方向変換。

public enum DTOMapperError: Error, Equatable {
    case invalidStatus(String)
    case invalidKind(String)
}

public enum DTOMapper {
    // MARK: PrincipalRef

    public static func toDTO(_ ref: PrincipalRef) -> PrincipalRefDTO {
        return PrincipalRefDTO(id: ref.id, kind: ref.kind.rawValue)
    }

    public static func fromDTO(_ dto: PrincipalRefDTO) throws -> PrincipalRef {
        guard let kind = PrincipalRef.Kind(rawValue: dto.kind) else {
            throw DTOMapperError.invalidKind(dto.kind)
        }
        return PrincipalRef(id: dto.id, kind: kind)
    }

    // MARK: IntentRef

    public static func toDTO(_ ref: IntentRef) -> IntentRefDTO {
        return IntentRefDTO(id: ref.id, version: ref.version)
    }

    public static func fromDTO(_ dto: IntentRefDTO) -> IntentRef {
        return IntentRef(id: dto.id, version: dto.version)
    }

    // MARK: Intent

    public static func toDTO(_ intent: Intent) -> IntentDTO {
        let (statusStr, reason): (String, String?) = {
            switch intent.status {
            case .active: return ("active", nil)
            case .closed(let reason): return ("closed", reason)
            }
        }()
        return IntentDTO(
            id: intent.id, version: intent.version,
            title: intent.title, body: intent.body,
            status: statusStr, closedReason: reason,
            parentId: intent.parentId
        )
    }

    // MARK: Verification

    public static func toDTO(_ check: VerificationCheck) -> VerificationCheckDTO {
        let (kindStr, spec): (String, String) = {
            switch check.kind {
            case .automated(let cmd): return ("automated", cmd)
            case .human(let inst): return ("human", inst)
            }
        }()
        let (statusStr, reason, by): (String, String?, PrincipalRefDTO?) = {
            switch check.status {
            case .pending: return ("pending", nil, nil)
            case .running: return ("running", nil, nil)
            case .passed: return ("passed", nil, nil)
            case .failed: return ("failed", nil, nil)
            case .waived(let reason, let by):
                return ("waived", reason, toDTO(by))
            }
        }()
        return VerificationCheckDTO(
            id: check.id, kind: kindStr, category: check.category,
            spec: spec, status: statusStr,
            waivedReason: reason, waivedBy: by,
            evidence: check.evidence, required: check.required
        )
    }

    // MARK: Task

    public static func toDTO(_ task: HoyTask) -> TaskDTO {
        return TaskDTO(
            id: task.id, intentId: task.intentId, title: task.title,
            createdBy: toDTO(task.createdBy),
            status: task.status.rawValue,
            dependsOn: task.dependsOn.map(toDTO),
            verifications: task.verifications.map(toDTO),
            completedSha: task.completedSha
        )
    }

    // MARK: AuditEntry

    public static func toDTO(_ entry: AuditEntry) -> AuditEntryDTO {
        return AuditEntryDTO(
            id: entry.id,
            timestamp: entry.timestamp.timeIntervalSince1970,
            actor: toDTO(entry.actor),
            op: entry.op,
            payload: entry.payload
        )
    }

    // MARK: Claim

    public static func toDTO(_ claim: Claim) -> ClaimDTO {
        return ClaimDTO(
            principal: toDTO(claim.principal),
            targetIntentId: claim.targetIntentId,
            acquiredAt: claim.acquiredAt.timeIntervalSince1970,
            expiresAt: claim.expiresAt.timeIntervalSince1970
        )
    }
}
