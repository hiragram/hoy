import Testing
import Foundation
@testable import HoyDaemon
@testable import HoyCore
@testable import HoyProtocol

/// docs/experiments/parallel-claim.md の手順に対応する統合テスト。
/// 2 Principal が並列に作業して claim と worktree が期待通りに動くことを確認。
struct ParallelClaimIntegrationTests {
    private let agentA = PrincipalRef(id: "agent-a", kind: .agent)
    private let agentB = PrincipalRef(id: "agent-b", kind: .agent)

    private func makeDispatcher() throws -> (Dispatcher, Workspace) {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-pci-\(UUID().uuidString)")
        let ws = try Workspace.open(at: root)
        return (Dispatcher(workspace: ws), ws)
    }

    private func encode<P: Codable & Sendable>(method: String, params: P) throws -> Data {
        return try JSONEncoder().encode(
            RPCRequest(id: UUID().uuidString, method: method, params: params)
        )
    }

    private func intentCreate(_ d: Dispatcher, title: String, actor: PrincipalRef) throws -> String {
        let req = try encode(
            method: Methods.IntentCreate.name,
            params: Methods.IntentCreate.Params(title: title)
        )
        let resp = try JSONDecoder().decode(
            RPCResponse<Methods.IntentCreate.Result>.self,
            from: d.handle(requestData: req, actor: actor)
        )
        return resp.result!.intent.id
    }

    private func taskCreate(_ d: Dispatcher, intentId: String, title: String, actor: PrincipalRef) throws -> String {
        let req = try encode(
            method: Methods.TaskCreate.name,
            params: Methods.TaskCreate.Params(intentId: intentId, title: title)
        )
        let resp = try JSONDecoder().decode(
            RPCResponse<Methods.TaskCreate.Result>.self,
            from: d.handle(requestData: req, actor: actor)
        )
        return resp.result!.task.id
    }

    @Test func differentIntents_independentClaims() throws {
        let (d, _) = try makeDispatcher()
        let iA = try intentCreate(d, title: "A", actor: agentA)
        let iB = try intentCreate(d, title: "B", actor: agentB)

        let claimAReq = try encode(
            method: Methods.ClaimAcquire.name,
            params: Methods.ClaimAcquire.Params(targetIntentId: iA, ttlSeconds: 60)
        )
        let claimBReq = try encode(
            method: Methods.ClaimAcquire.name,
            params: Methods.ClaimAcquire.Params(targetIntentId: iB, ttlSeconds: 60)
        )
        struct Empty: Codable, Sendable {}
        let respA = try JSONDecoder().decode(
            RPCResponse<Methods.ClaimAcquire.Result>.self,
            from: d.handle(requestData: claimAReq, actor: agentA)
        )
        let respB = try JSONDecoder().decode(
            RPCResponse<Methods.ClaimAcquire.Result>.self,
            from: d.handle(requestData: claimBReq, actor: agentB)
        )
        #expect(respA.result?.claim.principal.id == "agent-a")
        #expect(respB.result?.claim.principal.id == "agent-b")
    }

    @Test func sameIntent_secondClaimRejected() throws {
        let (d, _) = try makeDispatcher()
        let i = try intentCreate(d, title: "shared", actor: agentA)

        let req1 = try encode(
            method: Methods.ClaimAcquire.name,
            params: Methods.ClaimAcquire.Params(targetIntentId: i, ttlSeconds: 60)
        )
        _ = d.handle(requestData: req1, actor: agentA)

        let req2 = try encode(
            method: Methods.ClaimAcquire.name,
            params: Methods.ClaimAcquire.Params(targetIntentId: i, ttlSeconds: 60)
        )
        struct Empty: Codable, Sendable {}
        let resp = try JSONDecoder().decode(
            RPCResponse<Empty>.self,
            from: d.handle(requestData: req2, actor: agentB)
        )
        #expect(resp.error?.code == RPCErrorCode.conflict)
    }

    @Test func sharedFile_secondCompleteRaisesConflictEvent() throws {
        let (d, ws) = try makeDispatcher()
        // base に shared.txt
        let mainRepo = (ws.root as NSString).appendingPathComponent("repo")
        try "base".write(
            toFile: (mainRepo as NSString).appendingPathComponent("shared.txt"),
            atomically: true, encoding: .utf8
        )
        _ = try ws.git.commitAll(message: "base")

        let iA = try intentCreate(d, title: "A", actor: agentA)
        let iB = try intentCreate(d, title: "B", actor: agentB)
        let tA = try taskCreate(d, intentId: iA, title: "A", actor: agentA)
        let tB = try taskCreate(d, intentId: iB, title: "B", actor: agentB)

        // 各 task の worktree に編集を入れる
        let svc = TaskService(workspace: ws)
        let wA = try svc.ensureWorktree(forTask: tA)
        let wB = try svc.ensureWorktree(forTask: tB)
        try "from A".write(toFile: (wA as NSString).appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try "from B".write(toFile: (wB as NSString).appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)

        // EventBus を観測
        var seen: [String] = []
        let lock = NSLock()
        d.events.subscribe(filter: nil) { name, _ in
            lock.lock(); seen.append(name); lock.unlock()
        }

        // A complete → success
        let aReq = try encode(
            method: Methods.TaskComplete.name,
            params: Methods.TaskComplete.Params(id: tA)
        )
        let aResp = try JSONDecoder().decode(
            RPCResponse<Methods.TaskComplete.Result>.self,
            from: d.handle(requestData: aReq, actor: agentA)
        )
        #expect(aResp.error == nil)

        // B complete → conflict
        let bReq = try encode(
            method: Methods.TaskComplete.name,
            params: Methods.TaskComplete.Params(id: tB)
        )
        struct Empty: Codable, Sendable {}
        let bResp = try JSONDecoder().decode(
            RPCResponse<Empty>.self,
            from: d.handle(requestData: bReq, actor: agentB)
        )
        #expect(bResp.error?.code == RPCErrorCode.conflict)

        // 観測したイベントに task.completed と conflict.detected が含まれる
        lock.lock(); let snapshot = seen; lock.unlock()
        #expect(snapshot.contains(EventName.taskCompleted))
        #expect(snapshot.contains(EventName.conflictDetected))
    }
}
