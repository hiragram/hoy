# 0008. IntentはID安定+バージョン付き

- **Status**: Accepted
- **Related**: open-questions #1, #3

## Context

Intent は更新されうる(ADR 0005 の前提)。ID 振り直し方式(supersededリンク)と、ID 安定+内容更新方式が候補だった。後者を選んだ場合、内容履歴の扱い方として「単純上書き」と「バージョン付き」の2案があった。

## Decision

- Intent ID は安定(更新で変わらない)
- Intent は内部に **version 番号**を持ち、内容更新時に version が増える
- Task は通常 `intent_id` で参照(常に最新版を指す)
- 必要に応じて `intent_id@v3` のように特定版にピン留めできる

## Rationale

- ID 振り直し方式は参照整合性が地獄になる(Issue が "別 Issue に置き換わりました" 運用が機能していないのと同じ)
- 単純上書き案だと「Task が分解された時点の Intent」が失われ、ADR 0005 の needs-review フラグを正確に立てられない
- バージョン付きにすれば:
  - Task が派生した時点の Intent 版 を覚えておける → 差分検出が正確
  - 監査・振り返りで「なぜこの Task を切ったか」を当時の Intent 本文で追える
  - 単純上書き+audit log を精緻にしても結局バージョン管理の再発明になる

## Consequences

- Intent には `id` と `version` の2つのキーが存在
- ストレージ上、過去版の保持コストが発生(ただし Intent はテキスト中心で軽量なので問題にならない想定)
- Task → Intent 参照は「現在版を指す」がデフォルト、必要な場合のみピン留め
- needs-review フラグ(ADR 0005)は「Task が依拠していた version」と「現在の version」を比較して立てる
