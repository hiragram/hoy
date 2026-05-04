import Foundation
import HoyProtocol

/// hoy のメソッドを MCP ツール定義にマップする。
/// inputSchema は最小限。詳細スキーマはドキュメント生成段階で詰める。
public enum HoyTools {
    public static func all() -> [Tool] {
        return [
            tool("hoy_intent_create", "新しい Intent を作成", schema(properties: [
                "title": ("string", true),
                "body": ("string", false),
                "parentId": ("string", false)
            ])),
            tool("hoy_intent_get", "Intent を取得", schema(properties: [
                "id": ("string", true)
            ])),
            tool("hoy_intent_list", "Intent 一覧", schema(properties: [
                "parentId": ("string", false),
                "includeClosed": ("boolean", false)
            ])),
            tool("hoy_intent_update", "Intent を更新", schema(properties: [
                "id": ("string", true),
                "title": ("string", false),
                "body": ("string", false)
            ])),
            tool("hoy_intent_close", "Intent を close", schema(properties: [
                "id": ("string", true),
                "reason": ("string", true)
            ])),
            tool("hoy_task_create", "Task を作成", schema(properties: [
                "intentId": ("string", true),
                "title": ("string", true)
            ])),
            tool("hoy_task_get", "Task を取得", schema(properties: [
                "id": ("string", true)
            ])),
            tool("hoy_task_list", "Task 一覧", schema(properties: [
                "intentId": ("string", false)
            ])),
            tool("hoy_task_complete", "Task を完了 (commit=false でメタデータのみ、bypassVerifications=true で gate スキップ)", schema(properties: [
                "id": ("string", true),
                "commit": ("boolean", false),
                "bypassVerifications": ("boolean", false)
            ])),
            tool("hoy_task_close", "Task を close (キャンセル/別経路完了)", schema(properties: [
                "id": ("string", true),
                "reason": ("string", true)
            ])),
            tool("hoy_task_revert", "Task を revert", schema(properties: [
                "id": ("string", true)
            ])),
            tool("hoy_task_workspace", "Task の作業 worktree パスを返す", schema(properties: [
                "id": ("string", true)
            ])),
            tool("hoy_verification_add", "検証経路を追加", schema(properties: [
                "taskId": ("string", true),
                "kind": ("string", true),
                "category": ("string", true),
                "spec": ("string", true),
                "required": ("boolean", false)
            ])),
            tool("hoy_verification_run", "automated 検証を実行", schema(properties: [
                "taskId": ("string", true)
            ])),
            tool("hoy_verification_report", "human 検証結果を記録", schema(properties: [
                "taskId": ("string", true),
                "checkId": ("string", true),
                "passed": ("boolean", true),
                "evidence": ("string", false)
            ])),
            tool("hoy_verification_waive", "検証経路を waive", schema(properties: [
                "taskId": ("string", true),
                "checkId": ("string", true),
                "reason": ("string", true)
            ])),
            tool("hoy_claim_acquire", "Intent の claim を取得", schema(properties: [
                "targetIntentId": ("string", true),
                "ttlSeconds": ("number", false)
            ])),
            tool("hoy_claim_release", "claim を release", schema(properties: [
                "targetIntentId": ("string", true)
            ])),
            tool("hoy_claim_heartbeat", "claim のハートビート", schema(properties: [
                "targetIntentId": ("string", true),
                "ttlSeconds": ("number", false)
            ])),
        ]
    }

    /// MCP ツール名から hoy RPC メソッド名へ変換 (`hoy_intent_create` → `intent.create`)。
    public static func mapToolNameToRPCMethod(_ toolName: String) -> String? {
        guard toolName.hasPrefix("hoy_") else { return nil }
        let dropped = String(toolName.dropFirst("hoy_".count))
        let parts = dropped.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return "\(parts[0]).\(parts[1])"
    }

    private static func tool(_ name: String, _ desc: String, _ schema: JSONValue) -> Tool {
        return Tool(name: name, description: desc, inputSchema: schema)
    }

    private static func schema(properties: [String: (String, Bool)]) -> JSONValue {
        var props: [String: JSONValue] = [:]
        var required: [JSONValue] = []
        for (key, (type, isRequired)) in properties {
            props[key] = .object(["type": .string(type)])
            if isRequired { required.append(.string(key)) }
        }
        return .object([
            "type": .string("object"),
            "properties": .object(props),
            "required": .array(required)
        ])
    }
}
