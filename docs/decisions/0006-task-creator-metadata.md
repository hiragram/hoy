# 0006. Taskにcreated_byメタデータを持たせる

- **Status**: Accepted
- **Related**: open-questions #1, #4

## Context

Task の起票主体を人間/エージェントの両方に許容した(ADR 0003)結果、誰が起票したかを後から識別する必要が出る。

## Decision

Task に `created_by` メタデータを持たせる。値は `human(user_id)` または `agent(session_id)` の形を取る。

## Rationale

- 承認フロー(エージェントが起票した Task を人間が承認するか)の議論を可能にする
- 監査・トレーサビリティ(誰が・どのセッションで作ったか)に必須
- Intent 側にも同等のメタデータを持たせる方が一貫性がある(本 ADR は Task についてのみ確定し、Intent 側は別途扱う)

## Consequences

- エージェントセッションの ID 体系を別途決める必要がある
- 監査ログの基礎データになる(open-questions #4 のセキュリティ・権限モデルで再利用)
