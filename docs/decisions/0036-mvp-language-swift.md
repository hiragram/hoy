# 0036. MVP実装言語はSwift

- **Status**: Accepted
- **Related**: open-questions #6, #7

## Context

MVP の daemon・CLI の実装言語を選定する必要があった。候補として Rust / Go / TypeScript / Swift / Python を検討。

## Decision

**Swift で実装する**。

## Rationale

- 開発者本人(ユーザー)が読み書きできることが MVP段階では最重要
- 設計判断やコードレビューを自力でできないと、エージェント駆動開発が成立しない
- Swift の型システム・concurrency(async/await, actor)は daemon 設計と相性が良い
- Swift Argument Parser / SwiftNIO 等、必要な周辺ライブラリは揃っている

## 既知の懸念と対応

### Git ライブラリ

Swift で widely-used な Git ネイティブライブラリは存在しない。選択肢:

- (1) `git` コマンドの subprocess 実行 — MVP の最短ルート
- (2) libgit2 を C interop 経由で利用
- (3) 将来的に Rust の gitoxide を binding

MVP では (1) `git` subprocess を採用。性能要件が見えてから(2)(3)に移行する余地を残す。

### MCP SDK

Swift 公式 MCP SDK が存在しない場合は自前実装する(MCP は JSON-RPC over stdio ベースで実装可能)。仕様追随コストは負う。

### Linux サポート

Swift on Linux で daemon を動かす想定。macOS が一次プラットフォーム、Linux はベストエフォート。

### コントリビューター人口

OSS として広げるフェーズで dev tooling 系 Swift 使い手の少なさが摩擦になりうる。MVP 検証後の課題として認識する。

## Consequences

- daemon、CLI、MCPサーバすべて Swift で実装
- Git 操作は当面 `git` コマンドの subprocess 経由
- Swift Package Manager で配布
- 配布バイナリの target は macOS arm64 / x86_64 を初期サポート、Linux x86_64 はベストエフォート
- 将来的に書き直し or バインディングを充実させる選択肢を残す
