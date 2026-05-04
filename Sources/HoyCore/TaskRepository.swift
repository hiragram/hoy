import Foundation
import SQLite

public final class TaskRepository {
    private let storage: SQLiteStorage

    public init(storage: SQLiteStorage) {
        self.storage = storage
    }

    public func save(_ task: HoyTask) throws {
        try storage.db.transaction {
            try self.storage.db.run(
                """
                INSERT OR REPLACE INTO tasks
                (id, intent_id, title, created_by_id, created_by_kind, status, completed_sha)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                task.id,
                task.intentId,
                task.title,
                task.createdBy.id,
                task.createdBy.kind.rawValue,
                task.status.rawValue,
                task.completedSha
            )

            try self.storage.db.run("DELETE FROM task_dependencies WHERE task_id = ?", task.id)
            for dep in task.dependsOn {
                try self.storage.db.run(
                    """
                    INSERT INTO task_dependencies (task_id, intent_id, intent_version)
                    VALUES (?, ?, ?)
                    """,
                    task.id, dep.id, dep.version
                )
            }

            try self.storage.db.run("DELETE FROM verifications WHERE task_id = ?", task.id)
            for (index, check) in task.verifications.enumerated() {
                let (kind, spec) = Self.encodeKind(check.kind)
                let (statusStr, waivedReason, waivedById, waivedByKind) = Self.encodeStatus(check.status)
                try self.storage.db.run(
                    """
                    INSERT INTO verifications
                    (id, task_id, kind, category, spec, status,
                     waived_reason, waived_by_id, waived_by_kind, evidence, required, ordering,
                     test_first, red_observed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    check.id, task.id, kind, check.category, spec, statusStr,
                    waivedReason, waivedById, waivedByKind,
                    check.evidence, check.required ? 1 : 0, index,
                    check.testFirst ? 1 : 0, check.redObserved ? 1 : 0
                )
            }
        }
    }

    public func list(intentId: String? = nil) throws -> [HoyTask] {
        var sql = "SELECT id FROM tasks"
        var params: [Binding?] = []
        if let intentId {
            sql += " WHERE intent_id = ?"
            params.append(intentId)
        }
        sql += " ORDER BY id"
        var ids: [String] = []
        for row in try storage.db.prepare(sql, params) {
            ids.append(row[0] as! String)
        }
        var out: [HoyTask] = []
        for id in ids {
            if let t = try get(id: id) { out.append(t) }
        }
        return out
    }

    public func get(id: String) throws -> HoyTask? {
        let stmt = try storage.db.prepare(
            """
            SELECT id, intent_id, title, created_by_id, created_by_kind, status, completed_sha
            FROM tasks
            WHERE id = ?
            """,
            id
        )
        for row in stmt {
            let taskId = row[0] as! String
            let intentId = row[1] as! String
            let title = row[2] as! String
            let createdById = row[3] as! String
            let createdByKindStr = row[4] as! String
            let statusStr = row[5] as! String
            let completedSha = row[6] as? String

            guard let kind = PrincipalRef.Kind(rawValue: createdByKindStr) else {
                throw TaskRepositoryError.invalidPrincipalKind(createdByKindStr)
            }
            guard let status = HoyTask.Status(rawValue: statusStr) else {
                throw TaskRepositoryError.invalidStatus(statusStr)
            }

            let deps = try loadDependencies(taskId: taskId)
            let verifs = try loadVerifications(taskId: taskId)

            return HoyTask(
                id: taskId,
                intentId: intentId,
                title: title,
                createdBy: PrincipalRef(id: createdById, kind: kind),
                status: status,
                dependsOn: deps,
                verifications: verifs,
                completedSha: completedSha
            )
        }
        return nil
    }

    private func loadDependencies(taskId: String) throws -> [IntentRef] {
        let stmt = try storage.db.prepare(
            "SELECT intent_id, intent_version FROM task_dependencies WHERE task_id = ?",
            taskId
        )
        var refs: [IntentRef] = []
        for row in stmt {
            let id = row[0] as! String
            let version = Int(row[1] as! Int64)
            refs.append(IntentRef(id: id, version: version))
        }
        return refs
    }

    private func loadVerifications(taskId: String) throws -> [VerificationCheck] {
        let stmt = try storage.db.prepare(
            """
            SELECT id, kind, category, spec, status,
                   waived_reason, waived_by_id, waived_by_kind, evidence, required,
                   test_first, red_observed
            FROM verifications WHERE task_id = ?
            ORDER BY ordering ASC
            """,
            taskId
        )
        var out: [VerificationCheck] = []
        for row in stmt {
            let id = row[0] as! String
            let kindStr = row[1] as! String
            let category = row[2] as! String
            let spec = row[3] as! String
            let statusStr = row[4] as! String
            let waivedReason = row[5] as? String
            let waivedById = row[6] as? String
            let waivedByKindStr = row[7] as? String
            let evidence = row[8] as? String
            let required = (row[9] as! Int64) == 1
            let testFirst = (row[10] as! Int64) == 1
            let redObserved = (row[11] as! Int64) == 1

            let kind = try Self.decodeKind(kindStr: kindStr, spec: spec)
            let status = try Self.decodeStatus(
                statusStr: statusStr,
                waivedReason: waivedReason,
                waivedById: waivedById,
                waivedByKindStr: waivedByKindStr
            )

            out.append(VerificationCheck(
                id: id,
                kind: kind,
                category: category,
                status: status,
                required: required,
                evidence: evidence,
                testFirst: testFirst,
                redObserved: redObserved
            ))
        }
        return out
    }

    private static func encodeKind(_ kind: VerificationCheck.Kind) -> (String, String) {
        switch kind {
        case .automated(let cmd): return ("automated", cmd)
        case .human(let inst): return ("human", inst)
        }
    }

    private static func decodeKind(kindStr: String, spec: String) throws -> VerificationCheck.Kind {
        switch kindStr {
        case "automated": return .automated(command: spec)
        case "human": return .human(instruction: spec)
        default: throw TaskRepositoryError.invalidVerificationKind(kindStr)
        }
    }

    private static func encodeStatus(
        _ status: VerificationCheck.Status
    ) -> (String, String?, String?, String?) {
        switch status {
        case .pending: return ("pending", nil, nil, nil)
        case .running: return ("running", nil, nil, nil)
        case .passed: return ("passed", nil, nil, nil)
        case .failed: return ("failed", nil, nil, nil)
        case .waived(let reason, let by):
            return ("waived", reason, by.id, by.kind.rawValue)
        }
    }

    private static func decodeStatus(
        statusStr: String,
        waivedReason: String?,
        waivedById: String?,
        waivedByKindStr: String?
    ) throws -> VerificationCheck.Status {
        switch statusStr {
        case "pending": return .pending
        case "running": return .running
        case "passed": return .passed
        case "failed": return .failed
        case "waived":
            guard
                let reason = waivedReason,
                let id = waivedById,
                let kindStr = waivedByKindStr,
                let kind = PrincipalRef.Kind(rawValue: kindStr)
            else {
                throw TaskRepositoryError.invalidStatus("waived missing fields")
            }
            return .waived(reason: reason, by: PrincipalRef(id: id, kind: kind))
        default:
            throw TaskRepositoryError.invalidStatus(statusStr)
        }
    }
}

public enum TaskRepositoryError: Error, Equatable {
    case invalidStatus(String)
    case invalidPrincipalKind(String)
    case invalidVerificationKind(String)
}
