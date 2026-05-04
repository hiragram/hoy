# 0041. SQLite ライブラリは stephencelis/SQLite.swift を採用

- **Status**: Accepted
- **Related**: ADR 0036, ADR 0038

## Context

ADR 0038 で SQLite をメタデータストレージとして採用したが、Swift から SQLite を扱うライブラリは複数存在する。MVP 段階での選択を確定させる必要があった。

候補:

- (a) `stephencelis/SQLite.swift` — 古くからある型付きクエリビルダ系
- (b) Apple `sqlite3` C API を直接ラップ自作 — 依存最小だが車輪の再発明
- (c) `groue/GRDB.swift` — 高機能(マイグレーション、Combine 連携 等)、やや重量級

## Decision

`stephencelis/SQLite.swift` を採用する。

## Rationale

- 安定して widely-used。MVP のリスクを最小化できる
- 型付きクエリビルダがあり、Swift らしい記述で書ける
- 依存が軽量(SQLite 本体 + 薄いラッパー)
- 自作(b)は MVP の本旨(ドメインモデル中心)から外れる
- GRDB(c)は機能は豊富だが、当面必要のない抽象が多く、daemon の単一プロセス前提では恩恵が薄い

## Consequences

- `Package.swift` の依存に `stephencelis/SQLite.swift` を追加
- スキーマ定義・マイグレーションは別途設計(本ライブラリは軽量マイグレーション補助機能を持つ)
- 性能要件が見えた段階で C API 直叩きに置き換える余地は残す(ストレージ層をインタフェース抽象化しておけば差し替え可能、ADR 0040 の Consequences と整合)
