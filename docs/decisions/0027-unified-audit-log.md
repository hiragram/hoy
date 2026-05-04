# 0027. 監査ログはappend-onlyな統一ストリームとして持つ

- **Status**: Accepted
- **Related**: open-questions #4

## Context

「誰が何をしたか」を辿る情報が複数のADRに散らばっていた:
- ADR 0006: Task `created_by`
- ADR 0011: 強制release の記録
- ADR 0022: 未claim Intent の close 記録
- ADR 0025: Principal 識別

これらを統合するモデルを決める必要があった。

## Decision

全状態変更操作を **append-only な単一の監査ログストリーム**として記録する。エンティティ別履歴は監査ログの projection として導出する。

ログエントリの基本フィールド:

```
timestamp, principal_id, session_id, action_type, target (intent_id/task_id), payload
```

## Rationale

- セキュリティ監査の基本は append-only な統一ログ
- エンティティ内部に分散させると「Principal X が今日何をしたか」のような横断クエリが書けない
- daemon が内部で Git を使う(ADR 0013)ため、監査ログを Git の commit や notes 等に落とし込める可能性がある
- 単一 source of truth にすることで、エンティティ別ビューも統合分析ビューも同じデータから生成できる

## Consequences

- 監査ログ自体は immutable。修正はできず、訂正は新しいエントリで行う(差分として記録)
- ストレージは増え続けるが、構造化テキストなので問題にならない想定
- ログ形式は将来後方互換を保つ必要がある(プロトコルの一部)
- 「Intent X の履歴」「Principal Y の操作履歴」のようなクエリは projection として実装
- 削除要件(GDPRの忘れられる権利等)が将来出た場合、append-only との整合は別途検討
