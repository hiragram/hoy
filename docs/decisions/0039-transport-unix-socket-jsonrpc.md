# 0039. CLI/MCP のトランスポートは Unix domain socket + JSON-RPC

- **Status**: Accepted
- **Related**: ADR 0007, ADR 0015

## Context

daemon と CLI / MCP クライアントの通信方式を決める必要があった。候補:

- (a) Unix domain socket + JSON-RPC
- (b) gRPC
- (c) HTTP(REST または JSON-RPC over HTTP)

## Decision

**Unix domain socket + JSON-RPC** を採用する。

- daemon は Unix domain socket で listen
- CLI も MCP も同じソケットに接続し、JSON-RPC 2.0 でメッセージを送る
- MCP は仕様上 stdio または HTTP+SSE が標準だが、内部的に socket-via-JSON-RPC をベースにし、MCP サーバはその上のアダプタとして実装

## Rationale

- ローカル daemon (ADR 0015) 前提なので、TCP や HTTP は不要なオーバーヘッド
- Unix socket は OS のファイル権限で守れる(機密管理(ADR 0028)と整合)
- MCP プロトコル自体が JSON-RPC 2.0 ベースなので、内部統一感が高い
- gRPC は protobuf スキーマ管理が必要で初期コストが大きい。MVP には過剰
- HTTP は便利だが、ローカル daemon でポート開放するメリットが薄く、セキュリティ面で不利

## Consequences

- daemon は OS ファイル権限で socket を保護する(`0600` 等)
- ADR 0007 の「API一次・CLI/MCP は薄いラッパー」を JSON-RPC のメソッド名で表現できる(例: `intent.create`, `task.claim`, `verification.run`)
- リモート同期(ADR 0029 の将来拡張)が必要になったら、同じ JSON-RPC を TLS over TCP に移植する形で拡張可能
- Windows サポートが必要になった場合、Named Pipe への抽象化が必要(MVP では非対応)
- スキーマは別途定義する(ADR 0040 のプロトコル定義で扱う)
