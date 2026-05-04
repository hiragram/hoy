# Decision Log (ADR)

設計議論で決まった事項を1件1ファイルで積んでいく。ADR (Architecture Decision Record) 形式。

## ファイル命名

`NNNN-short-title.md` (例: `0001-intent-task-separation.md`)

## フォーマット

各ファイルの構成:

- **Status**: Proposed / Accepted / Superseded by NNNN
- **Context**: なぜこの議論が必要だったか
- **Decision**: 何を決めたか
- **Rationale**: なぜそう決めたか
- **Consequences**: この決定が引き起こす影響(良いものも悪いものも)
- **Related**: 関連するADR・open-questions項目

## 索引

| # | タイトル | Status | 関連open-question |
|---|---------|--------|------------------|
| [0001](0001-intent-task-separation.md) | IntentとTaskを別データ構造として分離 | Accepted | #1 |
| [0002](0002-platform-is-agent-agnostic.md) | プラットフォーム自体はエージェント機能を持たない | Accepted | #1 |
| [0003](0003-task-creation-actor.md) | Task起票主体は人間/エージェント両方を許容 | Accepted | #1 |
| [0004](0004-intent-nesting.md) | Intentは入れ子可、Taskは入れ子不可 | Accepted | #1 |
| [0005](0005-intent-update-propagation.md) | Intent更新時は子Taskにneeds-reviewフラグ | Accepted | #1, #3 |
| [0006](0006-task-creator-metadata.md) | Taskにcreated_byメタデータを持たせる | Accepted | #1, #4 |
| [0007](0007-cli-mcp-parity.md) | CLIとMCPは同等、APIが一次 | Accepted | #1 |
| [0008](0008-intent-versioning.md) | IntentはID安定+バージョン付き | Accepted | #1, #3 |
| [0009](0009-intent-exclusive-claim.md) | Intentは1エージェントによる排他claim | Accepted | #2 |
| [0010](0010-claim-granularity-independent.md) | 親Intentと子Intentは独立にclaim可能 | Accepted | #2 |
| [0011](0011-claim-liveness.md) | claim生存管理はハートビート+強制release | Accepted | #2 |
| [0012](0012-claim-semantics-write-exclusive.md) | claimは書き込み排他・読み取り自由 | Accepted | #2 |
| [0013](0013-task-changeset-storage.md) | Task変更セットは内部的にGitを再利用 | Accepted | #2 |
| [0014](0014-task-immediate-integration.md) | Task完了時に即時統合 | Accepted | #2 |
| [0015](0015-local-daemon-architecture.md) | hoyはローカル常駐daemon | Accepted | #2, #5 |
| [0016](0016-agent-dispatch-hook.md) | エージェント連携はhookスクリプト | Accepted | #2 |
| [0017](0017-conflict-resolution.md) | 統合コンフリクトは自動リベース→失敗時に差し戻し | Accepted | #2 |
| [0018](0018-task-cross-intent-dependency.md) | Task依存はIntent@versionで表現 | Accepted | #2 |
| [0019](0019-intent-lifecycle.md) | Intentはactive/closed + closing reason | Accepted | #3 |
| [0020](0020-intent-completion-trigger.md) | Intent完了は自動提案+明示承認 | Accepted | #3 |
| [0021](0021-intent-staleness-signals.md) | ドリフト検出はメタデータ提供のみ、判定は外部 | Accepted | #3 |
| [0022](0022-intent-close-authority.md) | Intent close権限はclaim者(未claim時は誰でも) | Accepted | #3 |
| [0023](0023-intent-no-reopen.md) | closed Intentのreopen不可 | Accepted | #3 |
| [0024](0024-task-cascade-close.md) | Intent close時に未完了Taskは自動close | Accepted | #3 |
| [0025](0025-principal-session-model.md) | claimはPrincipal単位、Session複数許容 | Accepted | #4 |
| [0026](0026-permission-model-mvp.md) | 権限制御はclaim駆動、capability細粒度は将来 | Accepted | #4 |
| [0027](0027-unified-audit-log.md) | 監査ログは統一append-onlyストリーム | Accepted | #4 |
| [0028](0028-no-builtin-secret-management.md) | 機密管理は内蔵せず外部secret manager前提 | Accepted | #4 |
| [0029](0029-mvp-single-developer.md) | MVPは単一開発者スコープ、マルチは将来 | Accepted | #5 |
| [0030](0030-fully-open-source.md) | hoyはフルOSS | Accepted | #6 |
| [0031](0031-mvp-scope.md) | MVPはデータモデル完備、UI・運用ツールは後 | Accepted | #6 |
| [0032](0032-mvp-no-external-integration.md) | MVPは外部ツール統合を持たない | Accepted | #6 |
| [0033](0033-no-internal-llm-cost.md) | hoy本体はLLM推論コストを内部負担しない | Accepted | #7 |
| [0034](0034-task-revert.md) | revertは一級操作、Taskを reverted 状態に遷移 | Accepted | #8 |
| [0035](0035-recovery-and-anomaly.md) | 復旧手段はMVP必須、暴走検知は外部hook | Accepted | #8 |
| [0036](0036-mvp-language-swift.md) | MVP実装言語はSwift | Accepted | — |
| [0037](0037-project-name-hoy.md) | プロジェクト名はhoy | Accepted | — |
