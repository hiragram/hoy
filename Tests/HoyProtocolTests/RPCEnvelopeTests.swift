import Testing
import Foundation
@testable import HoyProtocol

struct RPCEnvelopeTests {
    @Test func request_codableRoundTrip() throws {
        let req = RPCRequest(
            id: "req-1",
            method: Methods.IntentCreate.name,
            params: Methods.IntentCreate.Params(title: "ship")
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(RPCRequest<Methods.IntentCreate.Params>.self, from: data)
        #expect(decoded.id == "req-1")
        #expect(decoded.method == "intent.create")
        #expect(decoded.params.title == "ship")
        #expect(decoded.jsonrpc == "2.0")
    }

    @Test func response_resultEncoding() throws {
        let intent = IntentDTO(
            id: "i-1", version: 1, title: "x", body: "",
            status: "active", closedReason: nil, parentId: nil
        )
        let resp = RPCResponse<Methods.IntentCreate.Result>(
            id: "req-1",
            result: Methods.IntentCreate.Result(intent: intent)
        )
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(RPCResponse<Methods.IntentCreate.Result>.self, from: data)
        #expect(decoded.result?.intent == intent)
        #expect(decoded.error == nil)
    }

    @Test func errorResponse_encoding() throws {
        let resp = RPCResponse<Methods.IntentCreate.Result>(
            id: "req-1",
            error: RPCError(code: RPCErrorCode.notFound, message: "missing")
        )
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(RPCResponse<Methods.IntentCreate.Result>.self, from: data)
        #expect(decoded.error?.code == RPCErrorCode.notFound)
        #expect(decoded.result == nil)
    }
}

struct EventTests {
    @Test func taskCompletedEvent_roundTrip() throws {
        let env = EventEnvelope(
            method: EventName.taskCompleted,
            params: TaskCompletedEvent(taskId: "t-1", intentId: "i-1", sha: "abc")
        )
        let data = try JSONEncoder().encode(env)
        let decoded = try JSONDecoder().decode(EventEnvelope<TaskCompletedEvent>.self, from: data)
        #expect(decoded.method == "task.completed")
        #expect(decoded.params.taskId == "t-1")
    }
}
