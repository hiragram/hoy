# 0046. events.subscribe と通常 RPC は同一接続上で多重化できる

- **Status**: Accepted
- **Related**: ADR 0007, ADR 0039

## Context

ADR 0016 系の延長で `events.subscribe` を実装したが、以下が未確定だった:

- subscribe を投げた接続上で、続けて通常 RPC (intent.create 等) を投げられるか
- subscribe 専用接続を強制する設計にするか

## Decision

**同一接続で多重化を許す**。

- クライアントは 1 つの Unix socket 接続で `events.subscribe` を投げた後、同じ接続上で他の任意の RPC を投げてよい
- サーバ (daemon) は両者を区別する:
  - **応答**(response): `id` を持つ。subscribe や他の RPC のリクエストに対して 1:1 で返る
  - **通知**(notification): `id` を持たない `{"jsonrpc":"2.0","method":"...", "params":{...}}` 形式。subscribe 中の接続にのみ送られる
- クライアントは受信した JSON 行を `id` の有無で振り分ける

## Rationale

- JSON-RPC 2.0 仕様が応答と通知を区別する仕組みを既に持っており、追加プロトコルが不要
- agent の典型的なワークフロー(状態を購読しつつ操作も行う)が 1 接続で完結する
- 専用接続を強制すると agent 側の接続管理コストが増える
- 現実装(UnixSocketServer の永続接続化、ConnectionContext の async write、per-connection thread)で既に成立している。実験で `intent.create` を subscribe 後の同接続に投げて応答が返ることを確認済

## Consequences

- クライアント実装は received JSON ごとに `id` の有無を確認するパースを書く必要がある(MVP では `hoy events subscribe` は通知だけ表示する単純な listener として実装、将来の対話 client では多重化対応が必要)
- 接続単位の認証 (token) は subscribe 経由で受信する通知と通常 RPC の両方に同じ Principal を適用する。これは現実装通り
- 切断 (EOF) はそれが subscribe 接続か通常接続かを問わず ConnectionContext.performCleanup が走り、紐付いていた subscriber は EventBus から外れる
- HTTP/Streamable MCP gateway (ADR 0044) でも同じセマンティクスを保つ。gateway は 1 セッションを 1 daemon 接続に対応付ける想定

## 関連する未決事項

- 同接続上で複数の subscribe を投げた場合の挙動(現状は重複登録され通知が複数回届く)。MVP では未仕様、必要なら subscribe 解除 RPC を別途追加
- subscribe 中に接続が writeLock 競合で詰まったときの挙動(現実装は writeLock 取得待ち。タイムアウト付き drop は将来検討)
