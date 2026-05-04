import Foundation
import HoyProtocol

/// HTTP ダッシュボード本体。daemon に対しては既存の RPCClient で問い合わせる。
public final class DashboardServer: @unchecked Sendable {
    private let httpServer: HTTPServer
    private let rpc: RPCClient
    private let rootPath: String

    public init(port: Int, rpc: RPCClient, rootPath: String) {
        self.httpServer = HTTPServer(port: port)
        self.rpc = rpc
        self.rootPath = rootPath
    }

    public func start() throws {
        let rpc = self.rpc
        let rootPath = self.rootPath
        try httpServer.start { req in
            switch (req.method, req.path) {
            case ("GET", "/"):
                return HTTPResponse.ok(Data(DashboardHTML.page.utf8), contentType: "text/html; charset=utf-8")
            case ("GET", "/api/state"):
                let json = (try? Self.buildState(rpc: rpc, rootPath: rootPath)) ?? Data("{}".utf8)
                return HTTPResponse.ok(json, contentType: "application/json")
            case ("GET", "/api/events"):
                return .streaming(
                    headers: [
                        "Content-Type": "text/event-stream",
                        "Cache-Control": "no-store"
                    ],
                    onConnect: { writer in
                        Self.streamEvents(writer: writer, rpc: rpc)
                    }
                )
            default:
                return HTTPResponse.notFound()
            }
        }
    }

    /// daemon の events.subscribe に繋ぎ、受信した notification を SSE フレーム
    /// (`data: <json>\n\n`) として writer に流す。クライアント切断で終了。
    private static func streamEvents(writer: StreamWriter, rpc: RPCClient) {
        // ping を送って接続確認
        writer.send(": connected\n\n")
        try? rpc.subscribe(methods: nil) { line in
            guard let str = String(data: line, encoding: .utf8) else { return true }
            writer.send("data: \(str)\n\n")
            return true
        }
        writer.markClosed()
    }

    public func stop() {
        httpServer.stop()
    }

    /// daemon から intents/tasks/claims を取り出して JSON snapshot にする。
    /// ツリー構造は Intent の parentId を辿って再帰的に組み立てる。
    private static func buildState(rpc: RPCClient, rootPath: String) throws -> Data {
        // 全 Intent を 1 度に取りたいが API が parentId 指定しかない。
        // top-level → 子と再帰的に取得する。
        let claims = (try? rpc.call(
            Methods.ClaimList.self, params: Methods.ClaimList.Params()
        ).claims) ?? []

        let topLevel = try rpc.call(
            Methods.IntentList.self,
            params: Methods.IntentList.Params(parentId: nil, includeClosed: true)
        ).intents

        var nodes: [[String: Any]] = []
        for intent in topLevel {
            nodes.append(try buildNode(intent: intent, rpc: rpc))
        }

        let audit = (try? rpc.call(
            Methods.AuditTail.self, params: Methods.AuditTail.Params(limit: 30)
        ).entries) ?? []

        let payload: [String: Any] = [
            "root": rootPath,
            "ts": Date().timeIntervalSince1970,
            "claims": claims.map { c -> [String: Any] in
                return [
                    "principal": ["id": c.principal.id, "kind": c.principal.kind],
                    "targetIntentId": c.targetIntentId,
                    "acquiredAt": c.acquiredAt,
                    "expiresAt": c.expiresAt
                ]
            },
            "intents": nodes,
            "audit": audit.map { e -> [String: Any] in
                return [
                    "id": e.id,
                    "timestamp": e.timestamp,
                    "actor": ["id": e.actor.id, "kind": e.actor.kind],
                    "op": e.op,
                    "payload": e.payload
                ]
            }
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func buildNode(intent: IntentDTO, rpc: RPCClient) throws -> [String: Any] {
        let tasks = (try? rpc.call(
            Methods.TaskList.self,
            params: Methods.TaskList.Params(intentId: intent.id)
        ).tasks) ?? []
        let children = (try? rpc.call(
            Methods.IntentList.self,
            params: Methods.IntentList.Params(parentId: intent.id, includeClosed: true)
        ).intents) ?? []

        var node: [String: Any] = [
            "id": intent.id,
            "version": intent.version,
            "title": intent.title,
            "status": intent.status,
            "tasks": tasks.map { t -> [String: Any] in
                let verifs = t.verifications.map { v -> [String: Any] in
                    return [
                        "id": v.id,
                        "kind": v.kind,
                        "category": v.category,
                        "status": v.status,
                        "required": v.required
                    ]
                }
                return [
                    "id": t.id,
                    "title": t.title,
                    "status": t.status,
                    "verifications": verifs
                ]
            }
        ]
        if !children.isEmpty {
            node["children"] = try children.map { try buildNode(intent: $0, rpc: rpc) }
        }
        return node
    }
}
