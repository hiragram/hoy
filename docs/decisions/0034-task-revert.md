# 0034. revertは一級操作、Taskを `reverted` 状態に遷移させる

- **Status**: Accepted
- **Related**: open-questions #8

## Context

ADR 0014 で Task 完了時の即時統合を採用したため、問題のある変更が main に入る経路が短い。エージェントが壊れたコードを通したり、検証経路の穴で意図しない変更が入った場合の取り消し操作の意味論を定める必要があった。

選択肢:
- (a) Git の revert に丸投げ
- (b) compensating Task を生成
- (c) Task 自体を `reverted` 状態に遷移、裏で Git revert commit
- (d) Intent 単位の一括 revert

## Decision

**(c) を基本**: Task に `reverted` 状態を導入する。revert 操作で:

- 該当 Task の状態が `completed → reverted` に遷移
- daemon が裏で Git revert commit を打ち、main から該当変更が消える
- 監査ログに revert 実行が記録される(ADR 0027)

緊急時のエスケープハッチとして **(a) Git 直接操作**も残す(daemon 壊れた等の極限ケース)。エスケープハッチ使用後は daemon の状態と Git の状態に乖離が生じうるため、別途 reconciliation 操作が必要。

## Decision詳細

### revert に検証経路を要求するか

**要求する**。revert もコード変更の一形態であり、それ自体が壊れる可能性がある。Task の元の検証経路を再走させ、すべて passed になってから revert が確定する。

ただし「revert すべきもの自体が壊れている」状況では検証経路が通らないことがある。この場合は claim 者が `waived` 状態(ADR 0017 / VerificationCheck の `waived`)を使って明示的にスキップできる(理由必須)。

### Intent 単位の一括 revert

(d) は持たない。Intent 配下の複数 Task をまとめて revert したい場合は、各 Task に対して順次 revert 操作を実行する。一括コマンドはCLIの利便機能として提供してもよいが、データモデル上は Task 単位の revert の連続。

### revert 後の Intent 状態

- `reverted` 状態の Task は完了扱いではない
- Intent の completion 候補判定(ADR 0020)では「全必須 Task が `completed`」を要求するため、revert された Task が必須なら Intent は active のまま留まる
- 同じ目的の作業をやり直したい場合: 新しい Task を作るか、既存の `reverted` Task を再claimして再実装するかの選択は別途設計

## Rationale

- (a) のみだと nextgit データ層と Git 層が乖離する(Task は completed のままコードでは消えている)
- (b) は完全な工程やり直しになり重い
- (c) は revert を一級概念として持つことでデータモデル整合が自動的に取れる
- ADR 0023(closed Intent reopen不可)と同じく、「特殊操作はステータスとして明示」する方針と整合
- Git revert を裏で打つことで ADR 0013(Git内部利用)とも整合

## Consequences

- Task 状態に `reverted` を追加(`pending / claimed / completed / reverted / closed` 等)
- revert 操作は claim と同様に Principal 認証が必要
- revert 後の Git ログは「commit + revert commit」の2つが残る(履歴の透明性)
- 「reverted の reverted」(=revert を取り消して元に戻す)は混乱の元なので禁止する。やり直したいなら新 Task を作る
- daemon と Git の状態乖離検知のための reconciliation コマンドが必要
