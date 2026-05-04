# 0032. MVPは外部ツール統合を持たない

- **Status**: Accepted
- **Related**: open-questions #6

## Context

MVP段階で外部エコシステム(Git remote、IDE、Issue tracker等)との統合をどこまで持つかを決める必要があった。

## Decision

MVPでは外部ツール統合を**持たない**。具体的には:

### Git remote (GitHub/GitLab等)

- hoy daemon は Git remote を直接サポートしない
- コード共有が必要なら、既存の `git` コマンドで別途 push する
- Task 完了後の自動 push 等は agent-dispatch hook 内で実装可能(ユーザー責任)

### IDE 連携

- 専用の IDE プラグインは提供しない
- agent は MCP 経由で daemon に接続する
- IDE 上での操作は agent 経由で行う

### Issue tracker (Linear/Jira/GitHub Issues)

- 双方向統合は持たない
- Intent 本文に外部 URL を書ける程度で十分とする

## Rationale

- 外部統合の文脈を初期から取り込むと MVP の設計が歪み、本質的な検証が遅れる
- hoy の差別化価値はデータモデル(Intent/Task/検証経路/claim)であり、外部統合は後付け可能
- hook機構(ADR 0016)があれば、ユーザー側で必要な統合は実装できる
- ADR 0029 の「単一開発者MVP」と整合(チーム連携機能を持つ意味が薄い)

## Consequences

- MVP ユーザーは「コードは GitHub、Intent/Task は hoy ローカル」という二重管理を許容する必要がある
- 外部統合が欲しいユーザーは hook で自前実装する
- MVP 後のロードマップで「最初に統合すべき外部ツール」をユーザーフィードバックから決める
- ドキュメントには「hoy はコードホスティングではない」「既存 git remote と併用する」を明示する
