# 0042. テストフレームワークは Swift Testing

- **Status**: Accepted
- **Related**: ADR 0036, ADR 0040

## Context

ADR 0036 で MVP 言語を Swift に決めた後、テストフレームワークの選定が必要だった。候補:

- (a) XCTest — 従来、Apple 標準、IDE/CLI 双方で広範サポート
- (b) Swift Testing — Apple が新たに導入、Swift 5.10+/6 で標準同梱、`@Test` マクロ + `#expect` ベース

## Decision

**Swift Testing** を採用する。

## Rationale

- 表現力: `@Test` 関数 + `#expect(...)` で意図が読みやすい。失敗時の式分解で diagnostics が豊富
- パラメタライズドテスト・タグ・並列実行など、近代的な機能が標準
- Apple の今後の主流。XCTest はメンテモードへ移行する流れ
- Swift 6.0 ツールチェーン同梱で追加依存は不要(ADR 0036 と整合)
- `@testable import` 等は XCTest と同様に使える

## Consequences

- すべての新規テストは Swift Testing で書く(`import Testing`、`@Test`、`#expect`)
- XCTest を残す動機は当面なし。既存の placeholder テストも Swift Testing に置き換え済み
- IDE 統合は Xcode / VSCode (sourcekit-lsp) で対応済み
- Linux でも `swift test` が Swift Testing を実行できる(Swift 6.0+)
- 文書(CLAUDE.md / mvp-todo.md)に「テストは Swift Testing」と明記する
