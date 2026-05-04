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

    public init(workspace: Workspace) {
        self.workspace = workspace
        self.taskService = TaskService(workspace: workspace)
        self.verificationRunner = VerificationRunner(workspace: workspace)
    }

    private func audit(_ op: String, by actor: PrincipalRef, payload: [String: String]) {
        try? workspace.audit.append(AuditEntry.record(
            actor: actor, op: op, payload: payload, now: Date()
        ))
    }

    /// 1 リクエスト分の JSON Data を処理し、レスポンスの JSON Data を返す。
    /// principal は接続単位の認証で確定する想定 (Auth は呼出側)。
    public func handle(requestData: Data, actor: PrincipalRef) -> Data {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        // method 名を先に取り出すために envelope を 2 段階デコードする
        struct Header: Decodable { let id: String; let method: String }
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

        do {
            return try route(
                method: header.method,
                requestData: requestData,
                requestId: header.id,
                actor: actor,
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
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) throws -> Data {
        switch method {
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
                    parentId: params.parentId, includeClosed: params.includeClosed
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
                let check: VerificationCheck
                switch params.kind {
                case "automated":
                    check = VerificationCheck.automated(
                        category: params.category, command: params.spec, required: params.required
                    )
                case "human":
                    check = VerificationCheck.human(
                        category: params.category, instruction: params.spec, required: params.required
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
                let result = try self.taskService.complete(task: task, by: actor)
                return Methods.TaskComplete.Result(
                    task: DTOMapper.toDTO(result.task),
                    sha: result.sha
                )
            }

        case Methods.TaskRevert.name:
            return try handle(
                Methods.TaskRevert.self, data: requestData, id: requestId,
                decoder: decoder, encoder: encoder
            ) { params in
                let result = try self.taskService.revert(taskId: params.id, by: actor)
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
