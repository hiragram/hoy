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

    var rootPath: String { root ?? HoyPaths.defaultRoot() }
    var socketPath: String { socket ?? HoyPaths.defaultSocketPath(root: rootPath) }
}

// MARK: - daemon

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "daemon の起動・停止",
        subcommands: [Start.self]
    )

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
            FileHandle.standardError.write(Data("hoy daemon started: socket=\(options.socketPath)\n".utf8))
            // 永続的にブロック
            dispatchMain()
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
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.IntentList.self,
                params: Methods.IntentList.Params(
                    parentId: parentId, includeClosed: includeClosed
                )
            )
            for intent in result.intents {
                print("\(intent.id) v\(intent.version) [\(intent.status)] \(intent.title)")
            }
        }
    }

    struct Create: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument(help: "Intent タイトル") var title: String
        @Option var body: String = ""
        @Option(name: .customLong("parent")) var parentId: String?

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.IntentCreate.self,
                params: Methods.IntentCreate.Params(
                    title: title, body: body, parentId: parentId
                )
            )
            print("intent: \(result.intent.id) v\(result.intent.version) — \(result.intent.title)")
        }
    }

    struct Get: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.IntentGet.self,
                params: Methods.IntentGet.Params(id: id)
            )
            if let intent = result.intent {
                printIntent(intent)
            } else {
                print("not found: \(id)")
                throw ExitCode(1)
            }
        }
    }

    struct Update: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String
        @Option var title: String?
        @Option var body: String?

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.IntentUpdate.self,
                params: Methods.IntentUpdate.Params(id: id, title: title, body: body)
            )
            printIntent(result.intent)
        }
    }

    struct Close: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String
        @Option var reason: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.IntentClose.self,
                params: Methods.IntentClose.Params(id: id, reason: reason)
            )
            printIntent(result.intent)
        }
    }
}

// MARK: - task

struct TaskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task",
        subcommands: [Create.self, Get.self, List.self, Complete.self, Revert.self]
    )

    struct List: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("intent")) var intentId: String?

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.TaskList.self,
                params: Methods.TaskList.Params(intentId: intentId)
            )
            for task in result.tasks {
                print("\(task.id) [\(task.status)] \(task.title)  (intent=\(task.intentId))")
            }
        }
    }

    struct Create: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("intent")) var intentId: String
        @Argument var title: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.TaskCreate.self,
                params: Methods.TaskCreate.Params(intentId: intentId, title: title)
            )
            print("task: \(result.task.id) — \(result.task.title)")
        }
    }

    struct Get: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.TaskGet.self,
                params: Methods.TaskGet.Params(id: id)
            )
            if let task = result.task {
                printTask(task)
            } else {
                print("not found: \(id)")
                throw ExitCode(1)
            }
        }
    }

    struct Complete: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.TaskComplete.self,
                params: Methods.TaskComplete.Params(id: id)
            )
            print("completed: \(result.task.id) at \(result.sha)")
        }
    }

    struct Revert: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var id: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.TaskRevert.self,
                params: Methods.TaskRevert.Params(id: id)
            )
            print("reverted: \(result.task.id) revert-sha=\(result.revertSha)")
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
        @Option(name: .customLong("task")) var taskId: String
        @Option(help: "automated or human") var kind: String
        @Option var category: String
        @Option(help: "automated は実行コマンド、human は指示文") var spec: String
        @Flag(name: .customLong("optional"), inversion: .prefixedNo, exclusivity: .exclusive) var optional: Bool = false

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.VerificationAdd.self,
                params: Methods.VerificationAdd.Params(
                    taskId: taskId, kind: kind, category: category,
                    spec: spec, required: !optional
                )
            )
            printTask(result.task)
        }
    }

    struct Run: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("task")) var taskId: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.VerificationRun.self,
                params: Methods.VerificationRun.Params(taskId: taskId)
            )
            printTask(result.task)
        }
    }

    struct Report: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("task")) var taskId: String
        @Option(name: .customLong("check")) var checkId: String
        @Flag var failed: Bool = false
        @Option var evidence: String = ""

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.VerificationReport.self,
                params: Methods.VerificationReport.Params(
                    taskId: taskId, checkId: checkId,
                    passed: !failed, evidence: evidence
                )
            )
            printTask(result.task)
        }
    }

    struct Waive: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Option(name: .customLong("task")) var taskId: String
        @Option(name: .customLong("check")) var checkId: String
        @Option var reason: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.VerificationWaive.self,
                params: Methods.VerificationWaive.Params(
                    taskId: taskId, checkId: checkId, reason: reason
                )
            )
            printTask(result.task)
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
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.ClaimAcquire.self,
                params: Methods.ClaimAcquire.Params(
                    targetIntentId: intentId, ttlSeconds: ttl
                )
            )
            print("claimed: \(result.claim.targetIntentId) by \(result.claim.principal.id)")
        }
    }

    struct Release: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var intentId: String

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            _ = try client.call(
                Methods.ClaimRelease.self,
                params: Methods.ClaimRelease.Params(targetIntentId: intentId)
            )
            print("released: \(intentId)")
        }
    }

    struct Heartbeat: ParsableCommand {
        @OptionGroup var options: GlobalOptions
        @Argument var intentId: String
        @Option var ttl: Double = 300

        func run() throws {
            let client = RPCClient(socketPath: options.socketPath)
            let result = try client.call(
                Methods.ClaimHeartbeat.self,
                params: Methods.ClaimHeartbeat.Params(
                    targetIntentId: intentId, ttlSeconds: ttl
                )
            )
            print("heartbeat: \(result.claim.targetIntentId) expires=\(result.claim.expiresAt)")
        }
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
        let client = RPCClient(socketPath: options.socketPath)
        let server = MCPServer(tools: HoyTools.all()) { toolName, argsData in
            guard let method = HoyTools.mapToolNameToRPCMethod(toolName) else {
                return Data("{\"error\":\"unknown tool: \(toolName)\"}".utf8)
            }
            // tools/call は arguments を hoy method の params としてそのまま転送する。
            // RPCClient の薄いラッパは不要 — 直接 socket に投げる。
            return forwardRaw(method: method, paramsData: argsData, socketPath: client.socketPath)
        }
        server.run()
    }

    private func forwardRaw(method: String, paramsData: Data, socketPath: String) -> Data {
        // RPCRequest envelope を組み立てる
        let id = UUID().uuidString
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": (try? JSONSerialization.jsonObject(with: paramsData)) ?? [:]
        ]
        guard let reqData = try? JSONSerialization.data(withJSONObject: envelope) else {
            return Data("{\"error\":\"encode failed\"}".utf8)
        }
        return RawSocketSender.send(reqData, to: socketPath)
    }
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
