# 0025. claimはPrincipal単位、Sessionは複数許容

- **Status**: Accepted
- **Related**: open-questions #4

## Context

ADR 0009 で Intent claim を導入したが、「誰がclaimしているか」をプロセス単位で持つと不都合がある。例: hook で起動した子エージェントは別プロセスだが、親と同じclaim主体として振る舞ってほしい。

## Decision

3つの概念を分離する:

- **Principal**: claim主体を表す論理的なID(例: `claude-code-on-laptop`, `alice`)
- **Session**: daemon への接続単位(プロセス、MCP接続など)。1 Principal が複数 Session を持てる
- **Claim**: Principal 単位で確立される。Session が死んでも Principal が生きていれば claim 継続

認証は **token-based**。Principal に対して token が発行され、token を共有することで複数 Session が同じ Principal として振る舞える。

## Decision詳細

### claim確立の流れ

1. agent が Principal を名乗って認証 → daemon が token 発行
2. agent が token を使って Intent を claim → claim は Principal に紐づく
3. agent が子プロセスを起動する場合、token を環境変数等で引き継ぐ
4. 子プロセスが同じ token で接続 → 同じ Principal として認識される → claim への書き込み権限を持つ

### ハートビートとの関係(ADR 0011 の補完)

- ハートビートは Principal 単位で評価
- 同じ Principal の **いずれかの Session** がハートビートを送っていれば claim 維持
- 全 Session が落ちて一定時間経過 → 自動 release

### hook への token 受け渡し(ADR 0016 の補完)

hook ペイロードに claim 保持 Principal の token を含める:

```
NEXTGIT_PRINCIPAL_TOKEN=<token>
```

hook スクリプトは新規 agent 起動時にこの token を渡せる。これにより hook で起動した agent が同じ claim holder として振る舞う。

## Rationale

- プロセス単位だと hook 経由の子プロセスが claim 引き継げない
- OS user 単位は厳格すぎ、複数 agent ツール(Claude Code / Cursor 等)を同一マシンで使い分けるユースケースに合わない
- token-based + Principal は SSH agent / OAuth 等で実績のあるモデル
- Session 死亡 ≠ claim release なので、長時間 task を回す agent 運用が安定する

## Consequences

- daemon は Principal レジストリと token 発行機構を持つ
- token のライフサイクル(発行、失効、ローテーション)を別途設計
- token 漏洩時の影響範囲は当該 Principal のみ
- hook に token を渡すため、hook スクリプトとそれが起動するプロセスは信頼境界の内側に置く必要がある
- 「Session一覧を見る」「特定Sessionを切る」のような運用 API は別途設計
