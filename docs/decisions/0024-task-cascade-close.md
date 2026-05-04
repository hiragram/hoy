# 0024. Intent close時に未完了Taskは自動closeする

- **Status**: Accepted
- **Related**: open-questions #3

## Context

Intent が close されたとき、配下の未完了 Task をどう扱うかを定める必要があった。

## Decision

Intent が close された時点で、配下の **未完了 Task は自動 close される**。Task の closing reason には `parent_closed` を入れ、親 Intent の closing reason を辿れるようにする。

## Rationale

- Intent が `completed` で close される場合、必須 Task は ADR 0020 によりすべて完了している。残るのは任意 Task のみで、自動 close で問題ない
- `abandoned / obsolete / superseded` で close される場合、配下 Task に作業を続ける意味がないため自動 close が自然
- Task を手動で個別対応(iii-3)させる運用は煩雑で、Intent close の意図と矛盾しうる

## Consequences

- Task にも `closed_reason` フィールドが必要(`parent_closed` を含む)
- claim 中の Task が auto close される場合、claim も自動 release される
- claim 中エージェントには `task.cascaded_closed` 相当のイベントが発火し、hook 経由で通知される
- 親 Intent の closing reason は Task の `closed_reason` から辿れる(`parent_closed` → 親Intent参照)
