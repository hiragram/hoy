# 0040. モジュール構成: core / protocol / daemon / cli / mcp

- **Status**: Accepted
- **Related**: ADR 0007, ADR 0036, ADR 0039

## Context

Swift Package として実装するにあたり、モジュール(ターゲット)の分割方針を決める必要があった。

## Decision

以下のモジュール構成で開始する:

```
hoy/
├── Sources/
│   ├── HoyCore/        # データモデル、ストレージ、ビジネスロジック
│   ├── HoyProtocol/    # JSON-RPC のメッセージ型定義(client/server 共有)
│   ├── HoyDaemon/      # 常駐プロセス本体(socket listen、リクエスト処理)
│   ├── HoyCLI/         # CLI フロントエンド(daemon に接続)
│   └── HoyMCP/         # MCP サーバ(daemon に接続)
└── Tests/
    ├── HoyCoreTests/
    ├── HoyProtocolTests/
    ├── HoyDaemonTests/
    ├── HoyCLITests/
    └── HoyMCPTests/
```

## モジュールの責務

### HoyCore

- ドメインモデル(Intent / Task / VerificationCheck / Claim / AuditEntry 等)
- SQLite ストレージ層
- Git 操作層(`git` subprocess、ADR 0036)
- claim 管理ロジック(ハートビート、強制release)
- 統合処理(rebase、検証経路再走)
- イベント発行
- hook 起動

→ HoyCore は純粋なロジックライブラリ。トランスポートを知らない。

### HoyProtocol

- JSON-RPC のメソッド定義(リクエスト/レスポンス型)
- イベント定義(ADR 0016 の標準イベント等)
- バージョニング情報

→ client / server で同じ型を共有する。

### HoyDaemon

- Unix socket での listen(ADR 0039)
- 接続管理(Session、Principal 認証)
- HoyProtocol のリクエストを HoyCore に dispatch
- バックグラウンドジョブ(ハートビートチェック、検証経路実行など)

→ HoyDaemon は HoyCore + HoyProtocol を組み合わせる薄い層。

### HoyCLI

- CLI コマンド定義(Swift Argument Parser)
- daemon への接続と JSON-RPC 呼び出し
- 出力フォーマット(human readable / JSON)

### HoyMCP

- MCP プロトコル(JSON-RPC over stdio)の実装
- HoyProtocol のメソッドを MCP のツール定義として公開
- daemon への接続と中継

## Rationale

- ドメインロジック(HoyCore)とトランスポート(HoyDaemon/CLI/MCP)を分離することで、テストが書きやすくなる(ADR の TDD 規律と整合)
- HoyProtocol を別モジュールにすることで、client (CLI/MCP) と server (Daemon) で型定義を共有できる
- CLI と MCP は同じ JSON-RPC を叩く独立クライアント。ADR 0007 の「対称性」を実装レベルで保証
- 過剰に分割しない(機能ごとにモジュールを切り過ぎると逆に保守が辛くなる)

## Consequences

- 開発初期は HoyCore に注力、HoyDaemon は最小限のソケットdispatch、HoyCLI/MCP はスキャフォールド
- HoyCore が直接ファイルシステム・SQLite・git subprocess を叩く設計だと、テストで mock しにくい。インタフェース抽象を設けて DI する想定(別途設計)
- 実行バイナリは `hoy`(CLI兼daemon起動コマンド)1つに統合する想定。`hoy daemon start` のようなサブコマンドで daemon 起動。MCPサーバは `hoy mcp` で stdio mode 起動
- Swift Package Manager の `Package.swift` は本ADRの構成に従って初期化する
