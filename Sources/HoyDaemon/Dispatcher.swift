import Foundation
import HoyCore
import HoyProtocol

public enum DispatcherError: Error, Equatable {
    case unknownMethod(String)
    case invalidParams(String)
}

// JSON-RPC リクエストを HoyCore のサービス呼び出しに変換する dispatch 層。
// トランスポート (socket) からは独立。テスト時は raw Data で叩ける。
public final class Dispatcher: @unchecked Sendable {
    private let workspace: Workspace
    private let taskService: TaskService
    private let verificationRunner: VerificationRunner
    public let events: EventBus

    public init(workspace: Workspace, events: EventBus = EventBus()) {
        self.workspace = workspace
        self.taskService = TaskService(workspace: workspace)
        self.verificationRunner = VerificationRunner(workspace: workspace)
        self.events = events
    }

    private func publishEvent(_ name: String, payload: [String: String]) {
        let body: [String: Any] = ["jsonrpc": "2.0", "method": name, "params": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        events.publish(event: name, payload: data)
    }

    private func trace(method: String, requestId: String, actor: PrincipalRef, error: String? = nil) {
        let logPath = (workspace.root as NSString).appendingPathComponent("daemon.log")
        let ts = ISO8601DateFormatter().string(from: Date())
        var line = "[\(ts)] \(actor.id):\(actor.kind.rawValue) \(method) id=\(requestId)"
        if let error { line += " error=\(error)" }
        line += "\n"
        if let data = line.data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: logPath) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                _ = FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    private func audit(_ op: String, by actor: PrincipalRef, payload: [String: String]) {
        try? workspace.audit.append(AuditEntry.record(
            actor: actor, op: op, payload: payload, now: Date()
        ))
    }

    /// 1 リクエスト分の JSON Data を処理し、レスポンスの JSON Data を返す。
    /// `defaultActor` は token が付いていないリクエストの fallback。
    /// auth.token があれば SessionRepository で解決して上書きする。
    public func handle(
        requestData: Data,
        actor defaultActor: PrincipalRef,
        connection: UnixSocketServer.ConnectionContext? = nil
    ) -> Data {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        struct Header: Decodable {
            let id: String
            let method: String
            let auth: AuthInfo?
        }
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: requestData)
        } catch {
            return encodeError(
                id: "0",
                code: RPCErrorCode.parseError,
                message: "parse error",
                encoder: encoder
            )
        }

        // auth.token があれば Principal を解決
        var actor = defaultActor
        if let token = header.auth?.token {
            if let session = try? workspace.sessions.findByToken(token),
               let principal = try? workspace.principals.get(id: session.principalId) {
                actor = principal.ref
                // ハートビート的に lastSeenAt を更新
                try? workspace.sessions.save(session.touch(at: Date()))
            } else {
                return encodeError(
                    id: header.id, code: RPCErrorCode.unauthorized,
                    message: "invalid or expired token", encoder: encoder
                )
            }
        }

        defer { trace(method: header.method, requestId: header.id, actor: actor) }

        do {
            return try route(
                method: header.method,
                requestData: requestData,
                requestId: header.id,
                actor: actor,
                connection: connection,
                decoder: decoder,
                encoder: encoder
            )
        } catch let DispatcherError.unknownMethod(name) {
            return encodeError(
                id: header.id, code: RPCErrorCode.methodNotFound,
                message: "unknown method: \(name)", encoder: encoder
            )
        } catch let DispatcherError.invalidParams(detail) {
            return encodeError(
                id: header.id, code: RPCErrorCode.invalidParams,
                message: "invalid params: \(detail)", encoder: encoder
            )
        } catch {
            return encodeError(
                id: header.id, code: RPCErrorCode.internalError,
                message: String(describing: error), encoder: encoder
            )
        }
    }

    // MARK: - Routing

    private func route(
        method: String,
        requestData: Data,
        requestId: String,
        actor: PrincipalRef,
        connection: UnixSocketServer.ConnectionContext?,
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) throws -> Data {
        switch method {
        case Methods.EventsSubscribe.name:
            return try handle(
                Methods.EventsSubscribe.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                guard let conn = connection else {
                    throw makeRPCError(
                        code: RPCErrorCode.invalidState,
                        "events.subscribe requires a persistent connection"
                    )
                }
                let filter: Set<String>? = params.methods.map { Set($0) }
                let bus = self.events
                let subId = bus.subscribe(filter: filter) { _, payload in
                    conn.write(payload)
                }
                conn.addCleanup { bus.unsubscribe(id: subId) }
                return Methods.EventsSubscribe.Result(subscribed: params.methods)
            }

        case Methods.IntentCreate.name:
            return try handle(
                Methods.IntentCreate.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let intent = Intent.create(
                    title: params.title,
                    body: params.body ?? "",
                    parentId: params.parentId
                )
                try self.workspace.intents.save(intent)
                self.audit("intent.create", by: actor, payload: [
                    "intentId": intent.id, "title": intent.title
                ])
                return Methods.IntentCreate.Result(intent: DTOMapper.toDTO(intent))
            }

        case Methods.IntentGet.name:
            return try handle(
                Methods.IntentGet.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let intent = try self.workspace.intents.latest(id: params.id)
                return Methods.IntentGet.Result(intent: intent.map(DTOMapper.toDTO))
            }

        case Methods.IntentUpdate.name:
            return try handle(
                Methods.IntentUpdate.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                guard let current = try self.workspace.intents.latest(id: params.id) else {
                    throw makeRPCError(code: RPCErrorCode.notFound, "intent not found")
                }
                let updated = current.update(title: params.title, body: params.body)
                try self.workspace.intents.save(updated)
                self.audit("intent.update", by: actor, payload: [
                    "intentId": updated.id, "version": String(updated.version)
                ])
                return Methods.IntentUpdate.Result(intent: DTOMapper.toDTO(updated))
            }

        case Methods.IntentList.name:
            return try handle(
                Methods.IntentList.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let intents = try self.workspace.intents.list(
                    parentId: params.parentId,
                    includeClosed: params.includeClosed ?? false
                )
                return Methods.IntentList.Result(intents: intents.map(DTOMapper.toDTO))
            }

        case Methods.IntentClose.name:
            return try handle(
                Methods.IntentClose.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                guard let current = try self.workspace.intents.latest(id: params.id) else {
                    throw makeRPCError(code: RPCErrorCode.notFound, "intent not found")
                }
                let closed = try current.close(reason: params.reason)
                try self.workspace.intents.save(closed)

                // ADR 0024: 未完了 Task は cascade close
                let openStatuses: Set<HoyTask.Status> = [.open, .claimed, .inProgress]
                for task in try self.workspace.tasks.list(intentId: closed.id) {
                    if openStatuses.contains(task.status) {
                        try self.workspace.tasks.save(task.cascadeClose())
                    }
                }

                self.audit("intent.close", by: actor, payload: [
                    "intentId": closed.id, "reason": params.reason
                ])
                return Methods.IntentClose.Result(intent: DTOMapper.toDTO(closed))
            }

        case Methods.TaskCreate.name:
            return try handle(
                Methods.TaskCreate.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let task = HoyTask.create(
                    intentId: params.intentId,
                    title: params.title,
                    createdBy: actor,
                    dependsOn: params.dependsOn.map(DTOMapper.fromDTO)
                )
                try self.workspace.tasks.save(task)
                self.audit("task.create", by: actor, payload: [
                    "taskId": task.id, "intentId": task.intentId
                ])
                return Methods.TaskCreate.Result(task: DTOMapper.toDTO(task))
            }

        case Methods.TaskGet.name:
            return try handle(
                Methods.TaskGet.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let task = try self.workspace.tasks.get(id: params.id)
                return Methods.TaskGet.Result(task: task.map(DTOMapper.toDTO))
            }

        case Methods.TaskList.name:
            return try handle(
                Methods.TaskList.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let tasks = try self.workspace.tasks.list(intentId: params.intentId)
                return Methods.TaskList.Result(tasks: tasks.map(DTOMapper.toDTO))
            }

        case Methods.VerificationAdd.name:
            return try handle(
                Methods.VerificationAdd.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                guard let task = try self.workspace.tasks.get(id: params.taskId) else {
                    throw makeRPCError(code: RPCErrorCode.notFound, "task not found")
                }
                let required = params.required ?? true
                let check: VerificationCheck
                switch params.kind {
                case "automated":
                    check = VerificationCheck.automated(
                        category: params.category, command: params.spec, required: required
                    )
                case "human":
                    check = VerificationCheck.human(
                        category: params.category, instruction: params.spec, required: required
                    )
                default:
                    throw makeRPCError(
                        code: RPCErrorCode.invalidParams,
                        "kind must be automated or human"
                    )
                }
                let next = task.appendingVerification(check)
                try self.workspace.tasks.save(next)
                return Methods.VerificationAdd.Result(task: DTOMapper.toDTO(next))
            }

        case Methods.TaskComplete.name:
            return try handle(
                Methods.TaskComplete.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                guard let task = try self.workspace.tasks.get(id: params.id) else {
                    throw makeRPCError(code: RPCErrorCode.notFound, "task not found")
                }
                do {
                    let result = try self.taskService.complete(
                        task: task, by: actor,
                        commitChanges: params.commit ?? true,
                        bypassVerifications: params.bypassVerifications ?? false
                    )
                    self.publishEvent(EventName.taskCompleted, payload: [
                        "taskId": result.task.id,
                        "intentId": result.task.intentId,
                        "sha": result.sha
                    ])
                    for invalidatedId in result.invalidatedTaskIds {
                        self.publishEvent(EventName.verificationInvalidated, payload: [
                            "taskId": invalidatedId,
                            "reason": "main moved by task.complete \(result.task.id)"
                        ])
                    }
                    return Methods.TaskComplete.Result(
                        task: DTOMapper.toDTO(result.task),
                        sha: result.sha
                    )
                } catch let TaskServiceError.integrationConflict(stderr) {
                    self.publishEvent(EventName.conflictDetected, payload: [
                        "taskId": task.id, "intentId": task.intentId,
                        "stderr": stderr
                    ])
                    throw makeRPCError(
                        code: RPCErrorCode.conflict,
                        "integration conflict: \(stderr)"
                    )
                }
            }

        case Methods.TaskWorkspace.name:
            return try handle(
                Methods.TaskWorkspace.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                guard try self.workspace.tasks.get(id: params.id) != nil else {
                    throw makeRPCError(code: RPCErrorCode.notFound, "task not found")
                }
                let path = try self.taskService.ensureWorktree(forTask: params.id)
                return Methods.TaskWorkspace.Result(path: path)
            }

        case Methods.TaskClose.name:
            return try handle(
                Methods.TaskClose.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let result = try self.taskService.close(
                    taskId: params.id, by: actor, reason: params.reason
                )
                return Methods.TaskClose.Result(task: DTOMapper.toDTO(result.task))
            }

        case Methods.TaskRevert.name:
            return try handle(
                Methods.TaskRevert.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let result = try self.taskService.revert(taskId: params.id, by: actor)
                self.publishEvent(EventName.taskReverted, payload: [
                    "taskId": result.task.id,
                    "intentId": result.task.intentId,
                    "revertSha": result.revertSha
                ])
                return Methods.TaskRevert.Result(
                    task: DTOMapper.toDTO(result.task),
                    revertSha: result.revertSha
                )
            }

        case Methods.VerificationRun.name:
            return try handle(
                Methods.VerificationRun.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let task = try self.verificationRunner.runAutomated(taskId: params.taskId)
                return Methods.VerificationRun.Result(task: DTOMapper.toDTO(task))
            }

        case Methods.VerificationReport.name:
            return try handle(
                Methods.VerificationReport.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let task = try self.verificationRunner.recordHumanResult(
                    taskId: params.taskId, checkId: params.checkId,
                    passed: params.passed, evidence: params.evidence
                )
                return Methods.VerificationReport.Result(task: DTOMapper.toDTO(task))
            }

        case Methods.VerificationWaive.name:
            return try handle(
                Methods.VerificationWaive.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let task = try self.verificationRunner.waive(
                    taskId: params.taskId, checkId: params.checkId,
                    reason: params.reason, by: actor
                )
                return Methods.VerificationWaive.Result(task: DTOMapper.toDTO(task))
            }

        case Methods.SessionCreate.name:
            return try handle(
                Methods.SessionCreate.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                guard let kind = PrincipalRef.Kind(rawValue: params.kind) else {
                    throw makeRPCError(
                        code: RPCErrorCode.invalidParams,
                        "kind must be 'human' or 'agent'"
                    )
                }
                let principal: Principal
                if let existing = try self.workspace.principals.get(id: params.principalId) {
                    principal = existing
                } else {
                    principal = Principal(
                        id: params.principalId,
                        kind: kind,
                        displayName: params.displayName,
                        createdAt: Date()
                    )
                    try self.workspace.principals.save(principal)
                }
                let session = Session.start(for: principal, now: Date())
                try self.workspace.sessions.save(session)
                self.audit("session.create", by: actor, payload: [
                    "principalId": principal.id, "sessionId": session.id
                ])
                return Methods.SessionCreate.Result(
                    sessionId: session.id,
                    token: session.token,
                    principal: DTOMapper.toDTO(principal.ref)
                )
            }

        case Methods.SessionDelete.name:
            return try handle(
                Methods.SessionDelete.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                try self.workspace.storage.db.run(
                    "DELETE FROM sessions WHERE id = ?",
                    params.sessionId
                )
                self.audit("session.delete", by: actor, payload: [
                    "sessionId": params.sessionId
                ])
                return Methods.SessionDelete.Result()
            }

        case Methods.SessionWhoami.name:
            return try handle(
                Methods.SessionWhoami.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { _ in
                // 現在のリクエストの actor をそのまま返す
                return Methods.SessionWhoami.Result(
                    principal: DTOMapper.toDTO(actor),
                    sessionId: nil
                )
            }

        case Methods.ClaimList.name:
            return try handle(
                Methods.ClaimList.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { _ in
                let claims = try self.workspace.claims.list()
                return Methods.ClaimList.Result(
                    claims: claims.map(DTOMapper.toDTO)
                )
            }

        case Methods.ClaimAcquire.name:
            return try handle(
                Methods.ClaimAcquire.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let now = Date()
                let claim = Claim.acquire(
                    principal: actor,
                    targetIntentId: params.targetIntentId,
                    now: now,
                    ttl: params.ttlSeconds
                )
                try self.workspace.claims.acquire(claim, now: now)
                self.audit("claim.acquire", by: actor, payload: [
                    "intentId": claim.targetIntentId
                ])
                return Methods.ClaimAcquire.Result(claim: DTOMapper.toDTO(claim))
            }

        case Methods.ClaimRelease.name:
            return try handle(
                Methods.ClaimRelease.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { _ in
                try self.workspace.claims.release(
                    targetIntentId: try self.params(Methods.ClaimRelease.self,
                                                   data: requestData, decoder: decoder)
                        .targetIntentId,
                    by: actor
                )
                return Methods.ClaimRelease.Result()
            }

        case Methods.ClaimHeartbeat.name:
            return try handle(
                Methods.ClaimHeartbeat.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let now = Date()
                try self.workspace.claims.heartbeat(
                    targetIntentId: params.targetIntentId,
                    by: actor, now: now, ttl: params.ttlSeconds
                )
                guard let claim = try self.workspace.claims.get(targetIntentId: params.targetIntentId) else {
                    throw makeRPCError(code: RPCErrorCode.notFound, "claim not found")
                }
                return Methods.ClaimHeartbeat.Result(claim: DTOMapper.toDTO(claim))
            }

        default:
            throw DispatcherError.unknownMethod(method)
        }
    }

    // MARK: - Helpers

    private func handle<M: RPCMethod>(
        _ method: M.Type,
        data: Data,
        id: String,
        decoder: JSONDecoder,
        encoder: JSONEncoder,
        body: (M.Params) throws -> M.Result
    ) throws -> Data {
        let req: RPCRequest<M.Params>
        do {
            req = try decoder.decode(RPCRequest<M.Params>.self, from: data)
        } catch {
            throw DispatcherError.invalidParams(String(describing: error))
        }
        let result: M.Result
        do {
            result = try body(req.params)
        } catch let rpc as RPCErrorBox {
            return encodeError(id: id, code: rpc.error.code,
                               message: rpc.error.message, encoder: encoder)
        } catch let err as ClaimRepositoryError {
            return encodeError(
                id: id, code: RPCErrorCode.conflict,
                message: String(describing: err), encoder: encoder
            )
        } catch let err as IntentError {
            return encodeError(
                id: id, code: RPCErrorCode.invalidState,
                message: String(describing: err), encoder: encoder
            )
        } catch let err as HoyTaskError {
            return encodeError(
                id: id, code: RPCErrorCode.invalidState,
                message: String(describing: err), encoder: encoder
            )
        }
        let response = RPCResponse<M.Result>(id: id, result: result)
        return (try? encoder.encode(response)) ?? Data()
    }

    private func params<M: RPCMethod>(
        _ method: M.Type,
        data: Data,
        decoder: JSONDecoder
    ) throws -> M.Params {
        return try decoder.decode(RPCRequest<M.Params>.self, from: data).params
    }

    private func encodeError(
        id: String, code: Int, message: String, encoder: JSONEncoder
    ) -> Data {
        struct EmptyResult: Codable, Sendable { }
        let resp = RPCResponse<EmptyResult>(
            id: id,
            error: RPCError(code: code, message: message)
        )
        return (try? encoder.encode(resp)) ?? Data()
    }
}

// 内部用: HoyCore のエラーを RPC エラーに包んで投げるためのコンテナ
struct RPCErrorBox: Error {
    let error: RPCError
}

private func makeRPCError(code: Int, _ message: String) -> RPCErrorBox {
    return RPCErrorBox(error: RPCError(code: code, message: message))
}
