# 0031. MVPスコープ: データモデル完備、UI・運用ツールは後回し

- **Status**: Accepted
- **Related**: open-questions #6

## Context

これまで議論したADRをすべてMVPに含めると過大になる。MVPで何を必須・何を後回しにするかを決める必要があった。

## Decision

### MVP必須

- daemon バイナリ(常駐プロセス、ADR 0015)
- Intent / Task / 検証経路の CRUD API
- Intent の入れ子構造(ADR 0004)
- Intent バージョニング(ADR 0008)
- Task の `depends_on` フィールド(ADR 0018)— 機能としては最低限でも、データモデルとして必ず存在
- claim 機構(ADR 0009-0012)
- 検証経路の実行管理(automated / human、ADR 0017)
- 即時統合(ADR 0014)
- agent-dispatch hook 起動(ADR 0016)
- Git 内部利用(ADR 0013)
- MCP サーバ(ADR 0007)
- CLI(ADR 0007)
- Principal / Session / token モデル(ADR 0025)
- 最低限の監査ログ書き出し(ADR 0027)

### MVPで後回し

- Web UI / TUI(CLIのみで開始)
- ドリフト検出メタデータ(ADR 0021)
- クエリ可能な監査ログ機構(ADR 0027 のクエリ部分。書き出しは MVP に含む)
- 高度な権限・capability(ADR 0026 で将来拡張と明示済み)
- マルチ開発者対応(ADR 0029 で確定)

## Rationale

- データモデルは後付けがしんどい(既存データのマイグレーションが必要になる)→ 最初から完備
- UI・運用ツールは差別化要素ではなく、後付け可能 → MVP 外
- MCP 経由の agent が主クライアントなので CLI のみで実用に耐える
- 「機能はあるが UI が貧弱」状態は許容できる、「機能の根幹データが欠けている」状態は許容できない、という方針

## Consequences

- 初期ユーザー(自分含む dogfooding)は CLI と MCP 経由の agent で完結する操作で運用する
- 監査ログのクエリは初期は `grep` 等で対応
- Intent 入れ子・Task 依存はデータモデル上存在するが、初期 UI(CLI)では最小限の表示・編集機能のみ
- MVP フィードバックを元に、どの後回し機能を優先実装するかを決める
