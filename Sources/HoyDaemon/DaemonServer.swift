import Foundation
import HoyCore
import HoyProtocol

// daemon プロセス全体の起動・停止を司る薄い結合点。
// 実認証 (token → Principal) は Phase 5.1 後半で TokenAuthenticator として追加予定。
// 現状は接続単位で固定 Principal を使う最小構成。
public final class DaemonServer: @unchecked Sendable {
    public let socketPath: String
    private let workspace: Workspace
    private let dispatcher: Dispatcher
    private let server: UnixSocketServer
    private let actor: PrincipalRef
    private var purgeThread: Thread?
    private var running = false

    public init(workspace: Workspace, socketPath: String, actor: PrincipalRef) {
        self.workspace = workspace
        self.socketPath = socketPath
        self.dispatcher = Dispatcher(workspace: workspace)
        self.server = UnixSocketServer(path: socketPath)
        self.actor = actor
    }

    public func start() throws {
        let dispatcher = self.dispatcher
        let actor = self.actor
        try server.start { data, ctx in
            return dispatcher.handle(requestData: data, actor: actor, connection: ctx)
        }
        running = true
        startPurgeLoop()
    }

    public func stop() {
        running = false
        server.stop()
    }

    private func startPurgeLoop() {
        let workspace = self.workspace
        let bus = self.dispatcher.events
        let t = Thread { [weak self] in
            while self?.running == true {
                Thread.sleep(forTimeInterval: 5)
                guard let expired = try? workspace.claims.takeExpired(now: Date()) else { continue }
                for claim in expired {
                    let payload: [String: Any] = [
                        "jsonrpc": "2.0",
                        "method": EventName.claimExpired,
                        "params": [
                            "targetIntentId": claim.targetIntentId,
                            "principal": [
                                "id": claim.principal.id,
                                "kind": claim.principal.kind.rawValue
                            ]
                        ]
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: payload) {
                        bus.publish(event: EventName.claimExpired, payload: data)
                    }
                }
            }
        }
        t.name = "hoy-purge"
        purgeThread = t
        t.start()
    }
}
