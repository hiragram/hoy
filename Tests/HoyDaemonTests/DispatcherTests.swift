import Testing
import Foundation
@testable import HoyDaemon
@testable import HoyCore
@testable import HoyProtocol

struct DispatcherTests {
    private let actor = PrincipalRef(id: "agent-1", kind: .agent)

    private func makeDispatcher() throws -> Dispatcher {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-disp-\(UUID().uuidString)")
        let ws = try Workspace.open(at: root)
        return Dispatcher(workspace: ws)
    }

    private func encode<P: Codable & Sendable>(method: String, params: P) throws -> Data {
        return try JSONEncoder().encode(
            RPCRequest(id: "r1", method: method, params: params)
        )
    }

    @Test func intentCreate_returnsIntentDTO() throws {
        let d = try makeDispatcher()
        let req = try encode(
            method: Methods.IntentCreate.name,
            params: Methods.IntentCreate.Params(title: "ship")
        )
        let respData = d.handle(requestData: req, actor: actor)
        let resp = try JSONDecoder().decode(
            RPCResponse<Methods.IntentCreate.Result>.self, from: respData
        )
        #expect(resp.error == nil)
        #expect(resp.result?.intent.title == "ship")
        #expect(resp.result?.intent.version == 1)
    }

    @Test func intentGet_returnsSavedIntent() throws {
        let d = try makeDispatcher()
        let createReq = try encode(
            method: Methods.IntentCreate.name,
            params: Methods.IntentCreate.Params(title: "x")
        )
        let createResp = try JSONDecoder().decode(
            RPCResponse<Methods.IntentCreate.Result>.self,
            from: d.handle(requestData: createReq, actor: actor)
        )
        let id = createResp.result!.intent.id

        let getReq = try encode(
            method: Methods.IntentGet.name,
            params: Methods.IntentGet.Params(id: id)
        )
        let getResp = try JSONDecoder().decode(
            RPCResponse<Methods.IntentGet.Result>.self,
            from: d.handle(requestData: getReq, actor: actor)
        )
        #expect(getResp.result?.intent?.id == id)
    }

    @Test func taskCreate_thenComplete() throws {
        let d = try makeDispatcher()
        // intent
        let intentResp = try JSONDecoder().decode(
            RPCResponse<Methods.IntentCreate.Result>.self,
            from: d.handle(requestData: try encode(
                method: Methods.IntentCreate.name,
                params: Methods.IntentCreate.Params(title: "x")
            ), actor: actor)
        )
        let intentId = intentResp.result!.intent.id

        // task
        let taskResp = try JSONDecoder().decode(
            RPCResponse<Methods.TaskCreate.Result>.self,
            from: d.handle(requestData: try encode(
                method: Methods.TaskCreate.name,
                params: Methods.TaskCreate.Params(intentId: intentId, title: "do")
            ), actor: actor)
        )
        let taskId = taskResp.result!.task.id

        // complete
        let completeResp = try JSONDecoder().decode(
            RPCResponse<Methods.TaskComplete.Result>.self,
            from: d.handle(requestData: try encode(
                method: Methods.TaskComplete.name,
                params: Methods.TaskComplete.Params(id: taskId)
            ), actor: actor)
        )
        #expect(completeResp.error == nil)
        #expect(completeResp.result?.task.status == "completed")
        #expect(completeResp.result?.sha.count == 40)
    }

    @Test func unknownMethod_returnsMethodNotFound() throws {
        let d = try makeDispatcher()
        struct E: Codable, Sendable {}
        let req = try encode(method: "no.such.method", params: E())
        let respData = d.handle(requestData: req, actor: actor)
        struct EmptyResult: Codable, Sendable {}
        let resp = try JSONDecoder().decode(
            RPCResponse<EmptyResult>.self, from: respData
        )
        #expect(resp.error?.code == RPCErrorCode.methodNotFound)
    }

    @Test func malformedJson_returnsParseError() throws {
        let d = try makeDispatcher()
        let respData = d.handle(requestData: Data("not json".utf8), actor: actor)
        struct EmptyResult: Codable, Sendable {}
        let resp = try JSONDecoder().decode(
            RPCResponse<EmptyResult>.self, from: respData
        )
        #expect(resp.error?.code == RPCErrorCode.parseError)
    }

    @Test func claimConflict_returnsConflictError() throws {
        let d = try makeDispatcher()
        let intent = try JSONDecoder().decode(
            RPCResponse<Methods.IntentCreate.Result>.self,
            from: d.handle(requestData: try encode(
                method: Methods.IntentCreate.name,
                params: Methods.IntentCreate.Params(title: "x")
            ), actor: actor)
        ).result!.intent

        // 1st acquire
        _ = d.handle(requestData: try encode(
            method: Methods.ClaimAcquire.name,
            params: Methods.ClaimAcquire.Params(targetIntentId: intent.id, ttlSeconds: 60)
        ), actor: actor)

        // 2nd acquire by different principal
        let other = PrincipalRef(id: "agent-other", kind: .agent)
        let respData = d.handle(requestData: try encode(
            method: Methods.ClaimAcquire.name,
            params: Methods.ClaimAcquire.Params(targetIntentId: intent.id, ttlSeconds: 60)
        ), actor: other)
        struct EmptyResult: Codable, Sendable {}
        let resp = try JSONDecoder().decode(
            RPCResponse<EmptyResult>.self, from: respData
        )
        #expect(resp.error?.code == RPCErrorCode.conflict)
    }
}
