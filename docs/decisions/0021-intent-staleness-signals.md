# 0021. ドリフト検出は客観メタデータをdaemonが提供、判定は外部

- **Status**: Accepted
- **Related**: open-questions #3

## Context

Intent が陳腐化(放棄・ドリフト)していても誰も明示的に close しなければ active のまま残る。「3年後にノイズの山になる」リスクへの対処が必要。

選択肢:
- (a) プラットフォームは何もしない
- (b) 受動的サイン: 客観メタデータを提供
- (c) 能動的検出: LLM で意味的ドリフトを検知
- (d) 定期的な強制 needs-review

## Decision

- daemon は **客観メタデータ**(最終更新日時、最終 claim 日時、最終 commit 日時等)を Intent ごとに保持・公開する
- 「これは陳腐化している」という判定は daemon は行わない
- 意味レベルのドリフト検出が必要なら **外部 hook / CLI lister** が daemon のメタデータを読んで判断する(LLM を使うかどうかも外部の選択)

## Rationale

- 完全放置(a)は問題が解決しない
- 強制リマインダ(d)は needs-review がオオカミ少年化するリスクがあり乱用を招く
- 意味的ドリフト検出(c)は ADR 0002 の「プラットフォームはエージェント機能を持たない」と矛盾しやすい → 外部化することで整合
- 客観メタデータ(b)は軽量で副作用がなく、上位ロジック(自動アーカイブ・週次レビュー等)を外部で組める基盤になる

## Consequences

- Intent に活動メタデータ(`last_updated_at` / `last_claimed_at` / `last_commit_at` 等)を持たせる
- CLI 側で「90日アクティビティなしのIntent一覧」のような lister を提供する余地
- 「ドリフト判定 hook」をプロジェクト側で書けば、定期実行で自動 close 候補を出すこともできる(が、close は明示操作のまま)
- daemon は「stale」「obsolete」のような主観的フラグを持たない
