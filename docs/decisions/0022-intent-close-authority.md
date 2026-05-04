# 0022. Intentのclose権限はclaim者(未claim時は誰でも)

- **Status**: Accepted
- **Related**: open-questions #3

## Context

Intent を close できる主体を定める必要があった。close は書き込み操作であり、ADR 0012(claim中は書き込み排他)と整合させる必要がある。

## Decision

- Intent が **claim 中** の場合: **claim 者のみ** が close できる
- Intent が **未claim** の場合: **誰でも** close できる

## Rationale

- ADR 0009 / 0012 の「claim中は書き込み排他」を素直に拡張
- 未claim な Intent(放置されているもの)を整理できる経路を残す
- 作成者限定(i-2)は「作成者がもう関与していない」状況で詰む
- 状況で分ける(i-4)は分岐が増えて運用が複雑

## Consequences

- 強制 release(ADR 0011)で claim を奪った後、新たな claim 者が close できる
- 未claim な Intent の close は監査ログに残す(誰が・なぜ close したか)
- 親 Intent の claim 者が子 Intent を勝手に close することはできない(ADR 0010 で claim は独立)
