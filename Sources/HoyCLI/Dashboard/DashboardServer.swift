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
            default:
                return HTTPResponse.notFound()
            }
        }
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
            "intents": nodes
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
            "tasks": tasks.map { t in
                return ["id": t.id, "title": t.title, "status": t.status]
            }
        ]
        if !children.isEmpty {
            node["children"] = try children.map { try buildNode(intent: $0, rpc: rpc) }
        }
        return node
    }
}
