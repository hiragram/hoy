import Foundation
import ArgumentParser
import HoyCore
import HoyDaemon
import HoyProtocol
import HoyMCP

public struct HoyApp: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "hoy",
        abstract: "エージェント時代の開発プラットフォーム (MVP)",
        version: HoyProtocolVersion.current,
        subcommands: [
            DaemonCommand.self,
            IntentCommand.self,
            TaskCommand.self,
            VerificationCommand.self,
            ClaimCommand.self,
            MCPCommand.self,
            ReconcileCommand.self,
            BackupCommand.self,
            RestoreCommand.self,
            AuthCommand.self,
            EventsCommand.self,
        ]
    )

    public init() {}

    public static func main() {
        Self.main(nil)
    }
}

// MARK: - 共通オプション

struct GlobalOptions: ParsableArguments {
    @Option(name: .customLong("root"), help: "ワークスペース root ディレクトリ。既定は $HOY_ROOT または ~/.hoy/default")
    var root: String?

    @Option(name: .customLong("socket"), help: "Unix domain socket のパス")
    var socket: String?

    @Flag(name: .customLong("json"), help: "JSON で出力")
    var json: Bool = false

    var rootPath: String { root ?? HoyPaths.defaultRoot() }
    var socketPath: String { socket ?? HoyPaths.defaultSocketPath(root: rootPath) }

    func makeClient() -> RPCClient {
        let token = TokenStore.load(root: rootPath)?.token
        return RPCClient(socketPath: socketPath, token: token)
    }
}

func emit<T: Encodable>(_ value: T, json: Bool, human: () -> Void) {
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value),
           let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    } else {
        human()
    }
}

// MARK: - daemon

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "daemon の起動・停止",
        subcommands: [Start.self, Stop.self, Status.self]
    )

    static func pidFilePath(root: String) -> String {
        return (root as NSString).appendingPathComponent("daemon.pid")
    }

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "start", abstract: "daemon を起動 (フォアグラウンド)")

        @OptionGroup var options: GlobalOptions

        @Option(name: .customLong("principal-id"), help: "実行 Principal ID")
        var principalId: String = "local-dev"

        func run() throws {
            let workspace = try Workspace.open(at: options.rootPath)
            let actor = PrincipalRef(id: principalId, kind: .human)
            let server = DaemonServer(
                workspace: workspace,
                socketPath: options.socketPath,
                actor: actor
            )
            try server.start()

            let pid = ProcessInfo.processInfo.processIdentifier
            let pidPath = DaemonCommand.pidFilePath(root: options.rootPath)
            try "\(pid)\n".write(toFile: pidPath, atomically: true, encoding: .utf8)

            // SIGTERM で graceful shutdown
            let sigsrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            sigsrc.setEventHandler {
                server.stop()
                try? FileManager.default.removeItem(atPath: pidPath)
                Foundation.exit(0)
            }
            sigsrc.resume()
            signal(SIGTERM, SIG_IGN)

            FileHandle.standardError.write(Data("hoy daemon started: pid=\(pid) socket=\(options.socketPath)\n".utf8))
            dispatchMain()
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "stop", abstract: "起動中の daemon を停止")

        @OptionGroup var options: GlobalOptions

        func run() throws {
            let pidPath = DaemonCommand.pidFilePath(root: options.rootPath)
            guard let raw = try? String(contentsOfFile: pidPath, encoding: .utf8),
                  let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                print("daemon が起動していません (pid file なし)")
                throw ExitCode(1)
            }
            if kill(pid, SIGTERM) != 0 {
                print("kill failed errno=\(errno)")
                throw ExitCode(1)
            }
            print("stopped: pid=\(pid)")
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status", abstract: "daemon の生存確認")

        @OptionGroup var options: GlobalOptions

        func run() throws {
            let pidPath = DaemonCommand.pidFilePath(root: options.rootPath)
            if let raw = try? String(contentsOfFile: pidPath, encoding: .utf8),
               let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if kill(pid, 0) == 0 {
                    print("running: pid=\(pid) socket=\(options.socketPath)")
                    return
                }
            }
            print("not running")
            throw ExitCode(1)
        }
    }
}

// MARK: - intent

struct IntentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "intent",
        subcommands: [Create.self, Get.self, List.self, Update.self, Close.self]
    )

    struct List: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("parent")) var parentId: String?
        @Flag(name: .customLong("include-closed")) var includeClosed: Bool = false

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.IntentList.self,
                params: Methods.IntentList.Params(
                    parentId: parentId, includeClosed: includeClosed
                )
            )
            emit(result.intents, json: options.json) {
                for intent in result.intents {
                    print("\(intent.id) v\(intent.version) [\(intent.status)] \(intent.title)")
                }
            }
        }
    }

    struct Create: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument(help: "Intent タイトル") var title: String
        @Option var body: String = ""
        @Option(name: .customLong("parent")) var parentId: String?

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.IntentCreate.self,
                params: Methods.IntentCreate.Params(
                    title: title, body: body, parentId: parentId
                )
            )
            emit(result.intent, json: options.json) {
                print("intent: \(result.intent.id) v\(result.intent.version) — \(result.intent.title)")
            }
        }
    }

    struct Get: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.IntentGet.self,
                params: Methods.IntentGet.Params(id: id)
            )
            guard let intent = result.intent else {
                if options.json {
                    print("null")
                } else {
                    print("not found: \(id)")
                }
                throw ExitCode(1)
            }
            emit(intent, json: options.json) { printIntent(intent) }
        }
    }

    struct Update: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String
        @Option var title: String?
        @Option var body: String?

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.IntentUpdate.self,
                params: Methods.IntentUpdate.Params(id: id, title: title, body: body)
            )
            emit(result.intent, json: options.json) { printIntent(result.intent) }
        }
    }

    struct Close: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String
        @Option var reason: String

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.IntentClose.self,
                params: Methods.IntentClose.Params(id: id, reason: reason)
            )
            emit(result.intent, json: options.json) { printIntent(result.intent) }
        }
    }
}

// MARK: - task

struct TaskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task",
        subcommands: [Create.self, Get.self, List.self, Complete.self, Close.self, Revert.self]
    )

    struct Close: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String
        @Option var reason: String

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.TaskClose.self,
                params: Methods.TaskClose.Params(id: id, reason: reason)
            )
            emit(result.task, json: options.json) { printTask(result.task) }
        }
    }

    struct List: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("intent")) var intentId: String?

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.TaskList.self,
                params: Methods.TaskList.Params(intentId: intentId)
            )
            emit(result.tasks, json: options.json) {
                for task in result.tasks {
                    print("\(task.id) [\(task.status)] \(task.title)  (intent=\(task.intentId))")
                }
            }
        }
    }

    struct Create: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("intent")) var intentId: String
        @Argument var title: String

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.TaskCreate.self,
                params: Methods.TaskCreate.Params(intentId: intentId, title: title)
            )
            emit(result.task, json: options.json) {
                print("task: \(result.task.id) — \(result.task.title)")
            }
        }
    }

    struct Get: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.TaskGet.self,
                params: Methods.TaskGet.Params(id: id)
            )
            guard let task = result.task else {
                if options.json { print("null") } else { print("not found: \(id)") }
                throw ExitCode(1)
            }
            emit(task, json: options.json) { printTask(task) }
        }
    }

    struct Complete: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String
        @Flag(name: .customLong("no-commit"), help: "git commit を行わずメタデータだけ完了にする") var noCommit: Bool = false

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.TaskComplete.self,
                params: Methods.TaskComplete.Params(id: id, commit: !noCommit)
            )
            emit(result, json: options.json) {
                let suffix = result.sha.isEmpty ? "(metadata only)" : "at \(result.sha)"
                print("completed: \(result.task.id) \(suffix)")
            }
        }
    }

    struct Revert: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.TaskRevert.self,
                params: Methods.TaskRevert.Params(id: id)
            )
            emit(result, json: options.json) {
                print("reverted: \(result.task.id) revert-sha=\(result.revertSha)")
            }
        }
    }
}

// MARK: - verification

struct VerificationCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verification",
        subcommands: [Add.self, Run.self, Report.self, Waive.self]
    )

    struct Add: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument(help: "対象 Task ID") var taskId: String
        @Option(help: "automated or human") var kind: String
        @Option var category: String
        @Option(help: "automated は実行コマンド、human は指示文") var spec: String
        @Flag(name: .customLong("optional"), help: "required=false にする") var optional: Bool = false

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.VerificationAdd.self,
                params: Methods.VerificationAdd.Params(
                    taskId: taskId, kind: kind, category: category,
                    spec: spec, required: !optional
                )
            )
            emit(result.task, json: options.json) { printTask(result.task) }
        }
    }

    struct Run: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument(help: "対象 Task ID") var taskId: String

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.VerificationRun.self,
                params: Methods.VerificationRun.Params(taskId: taskId)
            )
            emit(result.task, json: options.json) { printTask(result.task) }
        }
    }

    struct Report: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument(help: "対象 Task ID") var taskId: String
        @Option(name: .customLong("check"), help: "VerificationCheck ID") var checkId: String
        @Flag(help: "passed の代わりに failed として記録") var failed: Bool = false
        @Option(help: "stdout/stderr など根拠の記録") var evidence: String = ""

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.VerificationReport.self,
                params: Methods.VerificationReport.Params(
                    taskId: taskId, checkId: checkId,
                    passed: !failed, evidence: evidence
                )
            )
            emit(result.task, json: options.json) { printTask(result.task) }
        }
    }

    struct Waive: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument(help: "対象 Task ID") var taskId: String
        @Option(name: .customLong("check"), help: "VerificationCheck ID") var checkId: String
        @Option var reason: String

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.VerificationWaive.self,
                params: Methods.VerificationWaive.Params(
                    taskId: taskId, checkId: checkId, reason: reason
                )
            )
            emit(result.task, json: options.json) { printTask(result.task) }
        }
    }
}

// MARK: - claim

struct ClaimCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claim",
        subcommands: [Acquire.self, Release.self, Heartbeat.self]
    )

    struct Acquire: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument(help: "対象 Intent ID") var intentId: String
        @Option(help: "TTL (秒)") var ttl: Double = 300

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.ClaimAcquire.self,
                params: Methods.ClaimAcquire.Params(
                    targetIntentId: intentId, ttlSeconds: ttl
                )
            )
            emit(result.claim, json: options.json) {
                print("claimed: \(result.claim.targetIntentId) by \(result.claim.principal.id)")
            }
        }
    }

    struct Release: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var intentId: String

        func run() throws {
            let client = options.makeClient()
            _ = try client.call(
                Methods.ClaimRelease.self,
                params: Methods.ClaimRelease.Params(targetIntentId: intentId)
            )
            struct Released: Encodable { let released: String }
            emit(Released(released: intentId), json: options.json) {
                print("released: \(intentId)")
            }
        }
    }

    struct Heartbeat: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var intentId: String
        @Option var ttl: Double = 300

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.ClaimHeartbeat.self,
                params: Methods.ClaimHeartbeat.Params(
                    targetIntentId: intentId, ttlSeconds: ttl
                )
            )
            emit(result.claim, json: options.json) {
                print("heartbeat: \(result.claim.targetIntentId) expires=\(result.claim.expiresAt)")
            }
        }
    }
}

// MARK: - events

struct EventsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "daemon からのイベントを購読",
        subcommands: [Subscribe.self]
    )

    struct Subscribe: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "subscribe",
            abstract: "task.completed / task.reverted などを stream で受信"
        )

        @OptionGroup var options: GlobalOptions
        @Option(help: "method 名を絞り込む (カンマ区切り)") var methods: String?

        func run() throws {
            let client = options.makeClient()
            let filter = methods?.split(separator: ",").map { String($0) }
            FileHandle.standardError.write(Data("subscribed. press Ctrl-C to stop.\n".utf8))
            try client.subscribe(methods: filter) { line in
                FileHandle.standardOutput.write(line)
                FileHandle.standardOutput.write(Data("\n".utf8))
                return true
            }
        }
    }
}

// MARK: - auth

struct AuthCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Principal/Session の管理",
        subcommands: [Login.self, Logout.self, Whoami.self]
    )

    struct Login: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "login", abstract: "Principal を作成 (なければ) し token を発行 / 保存")

        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("principal-id"), help: "Principal ID (一意)") var principalId: String
        @Option(help: "human or agent") var kind: String = "human"
        @Option(name: .customLong("display-name"), help: "表示名") var displayName: String

        func run() throws {
            // 認証なしで session.create を叩く (token なしで OK)
            let client = RPCClient(socketPath: options.socketPath, token: nil)
            let result = try client.call(
                Methods.SessionCreate.self,
                params: Methods.SessionCreate.Params(
                    principalId: principalId, kind: kind, displayName: displayName
                )
            )
            try TokenStore.save(
                StoredToken(
                    sessionId: result.sessionId,
                    token: result.token,
                    principalId: result.principal.id
                ),
                root: options.rootPath
            )
            emit(result, json: options.json) {
                print("logged in: principal=\(result.principal.id) session=\(result.sessionId)")
                print("token saved to \(TokenStore.path(root: options.rootPath))")
            }
        }
    }

    struct Logout: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "logout", abstract: "Session を破棄して token を削除")

        @OptionGroup var options: GlobalOptions

        func run() throws {
            guard let stored = TokenStore.load(root: options.rootPath) else {
                print("not logged in")
                return
            }
            let client = options.makeClient()
            _ = try? client.call(
                Methods.SessionDelete.self,
                params: Methods.SessionDelete.Params(sessionId: stored.sessionId)
            )
            TokenStore.clear(root: options.rootPath)
            print("logged out")
        }
    }

    struct Whoami: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "whoami", abstract: "現在の token から解決される Principal を表示")

        @OptionGroup var options: GlobalOptions

        func run() throws {
            let client = options.makeClient()
            let result = try client.call(
                Methods.SessionWhoami.self,
                params: Methods.SessionWhoami.Params()
            )
            emit(result.principal, json: options.json) {
                print("\(result.principal.id) (\(result.principal.kind))")
            }
        }
    }
}

// MARK: - reconcile / backup

struct ReconcileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reconcile",
        abstract: "SQLite と Git の整合性をチェック (ADR 0035)"
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        // daemon を経由せず直接 Workspace を開く
        let ws = try Workspace.open(at: options.rootPath)
        let report = try Reconciliation(workspace: ws).check()
        if report.isClean {
            print("clean")
            return
        }
        if !report.missingShas.isEmpty {
            print("missing shas:")
            for sha in report.missingShas { print("  - \(sha)") }
        }
        throw ExitCode(1)
    }
}

struct BackupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "state.db と repo を指定先にスナップショット"
    )

    @OptionGroup var options: GlobalOptions
    @Argument(help: "保存先ディレクトリ") var destination: String

    func run() throws {
        let ws = try Workspace.open(at: options.rootPath)
        let path = try Backup(workspace: ws).snapshot(to: destination)
        print("snapshot: \(path)")
    }
}

struct RestoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "snapshot から root を復元 (daemon 停止中に実行)"
    )

    @OptionGroup var options: GlobalOptions
    @Argument(help: "snapshot ディレクトリ") var snapshot: String

    func run() throws {
        try Backup.restore(from: snapshot, into: options.rootPath)
        print("restored to \(options.rootPath)")
    }
}

// MARK: - mcp

struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP サーバを stdio モードで起動 (daemon に中継)"
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let client = options.makeClient()
        let socketPath = client.socketPath
        let token = client.token
        let server = MCPServer(tools: HoyTools.all()) { toolName, argsData in
            guard let method = HoyTools.mapToolNameToRPCMethod(toolName) else {
                return Data("{\"error\":\"unknown tool: \(toolName)\"}".utf8)
            }
            return forwardRaw(
                method: method, paramsData: argsData,
                socketPath: socketPath, token: token
            )
        }
        server.run()
    }
}

private func forwardRaw(
    method: String, paramsData: Data, socketPath: String, token: String?
) -> Data {
    let id = UUID().uuidString
    var envelope: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id,
        "method": method,
        "params": (try? JSONSerialization.jsonObject(with: paramsData)) ?? [:]
    ]
    if let token { envelope["auth"] = ["token": token] }
    guard let reqData = try? JSONSerialization.data(withJSONObject: envelope) else {
        return Data("{\"error\":\"encode failed\"}".utf8)
    }
    return RawSocketSender.send(reqData, to: socketPath)
}

enum RawSocketSender {
    static func send(_ payload: Data, to path: String) -> Data {
        let client = RPCClient(socketPath: path)
        return (try? client.rawSend(payload)) ?? Data("{\"error\":\"socket failed\"}".utf8)
    }
}

// MARK: - 印字ヘルパ

private func printIntent(_ intent: IntentDTO) {
    print("id:      \(intent.id)")
    print("version: \(intent.version)")
    print("title:   \(intent.title)")
    print("status:  \(intent.status)\(intent.closedReason.map { " (\($0))" } ?? "")")
    if let parent = intent.parentId { print("parent:  \(parent)") }
    if !intent.body.isEmpty {
        print("body:")
        print(intent.body)
    }
}

private func printTask(_ task: TaskDTO) {
    print("id:      \(task.id)")
    print("intent:  \(task.intentId)")
    print("title:   \(task.title)")
    print("status:  \(task.status)")
    if let sha = task.completedSha { print("sha:     \(sha)") }
    if !task.verifications.isEmpty {
        print("checks:")
        for v in task.verifications {
            let req = v.required ? " [required]" : ""
            print("  - [\(v.status)] \(v.kind):\(v.category)\(req)")
        }
    }
}
