# 0044. MCP の HTTP/Streamable 転送は共有ゲートウェイで提供する

- **Status**: Proposed
- **Related**: ADR 0007, ADR 0015, ADR 0029, ADR 0039

## Context

現状、`hoy mcp` は stdio モードのみを実装している(MCPServer)。クライアント(Claude Desktop 等)が `hoy mcp` を子プロセスとして spawn し、stdin/stdout で JSON-RPC を交換する。この経路は TCP を使わないのでポート衝突は起きない。

一方、MCP には HTTP / Streamable HTTP 転送がある。Web ベースのクライアントやリモートエージェントから接続するには HTTP 転送が必要になる。

ここで、hoy daemon が **1 daemon = 1 workspace = 1 repo** という per-repo モデル(ADR 0015 の素直な実装、Unix socket は `<root>/socket`)を取っているため、HTTP 転送をどう載せるかが論点になる。

## 論点

リポを 3 つ並行で開発しているとすると、daemon プロセスは 3 つ走っている。それぞれが HTTP MCP サーバを立てると:

- 各 daemon が TCP ポートを開く必要がある
- デフォルトポート決め打ちは一発で衝突する
- クライアントの MCP 設定にリポ数だけサーバ定義を並べる羽目になる
- 認証(将来の token 認証、ADR 0025)を各 daemon に重複で組み込む必要がある

## 検討した選択肢

### (a) 各 daemon が個別に HTTP ポートを持つ

- 起動時に固定ポート (例 8765) を listen、衝突時はエラー
- または OS から空きポートを取得し `<root>/mcp.port` に書き出す
- 利点: 実装が daemon 内に閉じる
- 欠点: クライアント側で「リポ A のポート」「リポ B のポート」を別々に管理する必要がある。エージェント時代の運用感に合わない

### (b) 単一 MCP HTTP ゲートウェイ

```
Claude / Web client ─HTTP─▶ hoy-mcp-gateway :PORT
                                  │
                       ┌──────────┼──────────┐
                       ▼          ▼          ▼ (Unix socket)
                  daemon(A)   daemon(B)   daemon(C)
```

- 1 プロセスが HTTP listen し、URL パス(例 `/workspaces/<id>/`)または header で対象 daemon を振り分け
- gateway が各 daemon の Unix socket に JSON-RPC を転送、Streamable な応答を多重化
- 利点: クライアント側の MCP 設定が 1 個で済む / 認証集約点ができる / per-repo daemon のシンプルさを維持
- 欠点: gateway が単一障害点になる。実装すべきコードが増える

### (c) 単一 daemon が複数 workspace を抱える

- daemon 自身を multi-workspace 化する
- HTTP ポート問題は副次的に解決する
- 利点: 階層構造がフラットになる
- 欠点: per-repo daemon の状態完全分離(クラッシュ局所化、デバッグ容易性)を捨てることになる。MVP ではメリットが小さい

## Decision

**(b) 単一 MCP HTTP ゲートウェイ方式を採用する**。

- daemon は引き続き **1 workspace = 1 daemon = 1 socket** のままにする(ADR 0015 の延長線上)
- HTTP / Streamable MCP が要るユースケースが出てきた段階で、`hoy-mcp-gateway` を別バイナリ(あるいは `hoy gateway start` サブコマンド)として導入する
- gateway はローカルに起動するだけの集約レイヤ。各 daemon の Unix socket に対して逆プロキシ的に振る舞う
- 認証(token、ADR 0025)は gateway 入口で行う設計にする(daemon 側は引き続きローカル前提)

実装は本 ADR 採択時点では未着手。`docs/mvp-todo.md` の「Phase 6.2 MCP サーバ」の延長として将来追加する。

## Rationale

- **エージェント時代のクライアント設定はミニマルでありたい**: Claude Desktop の MCP 設定に N 個のサーバを並べる UX は agentic ワークフローと噛み合わない。1 エンドポイントで全 workspace を扱える gateway は agent の認知負荷を最小化する
- **per-repo daemon の利点を捨てたくない**: 状態完全分離(state.db / repo / pid / socket がすべて root スコープ)は dogfooding 期で特に効く。gateway 方式ならこの利点を温存できる
- **Streamable は接続多重化に向いている**: HTTP/2 や SSE での長寿命接続は gateway で多重化するのが自然。各 daemon が独立に Streamable を喋るより gateway 集約のほうがプロトコル設計上クリーン
- **認証の集約点が必要**: ローカル Unix socket は OS 権限で守れる(ADR 0028, 0039)が、HTTP は token 認証(将来 ADR 0025 拡張)が必須。gateway があれば認証はそこに集約できる

## Consequences

- 短期: stdio MCP のみで運用する。`hoy mcp` を子プロセスで spawn する Claude Desktop 等の構成では何も変わらない
- 中期: HTTP MCP が必要になった時点で `hoy-mcp-gateway` を起こす。MVP 範囲外(ADR 0031 の MVP スコープに gateway は含まない)
- gateway 経由で接続するクライアントは workspace を URL かヘッダで指定する必要が出る。プロトコル詳細(`/workspaces/<id>/mcp` か、`X-Hoy-Workspace` ヘッダか等)は gateway 実装時に別 ADR で確定する
- per-repo daemon 自体には HTTP/TCP リスナーを生やさない。これは方針として明文化する
- 単一障害点(gateway)が現実化したらフォールバックとして stdio MCP に逃げられる。冗長性は当面これで足りる

## 関連する未決事項

- gateway の workspace 解決方式(URL path / header / subdomain)
- daemon 自動発見(gateway がどう daemon を見つけるか — fixed registry vs. discovery)
- gateway 自体の起動方式(常駐 / on-demand / launchd)
- gateway 経由で stdio MCP との対称性をどう保つか
