# 0010. 親Intentと子Intentは独立にclaimできる

- **Status**: Accepted
- **Related**: open-questions #2

## Context

ADR 0004 で Intent は入れ子可能とした。ADR 0009 で Intent ごとに排他 claim を導入した結果、親 Intent を claim したときに子 Intent も自動ロックされるかが論点になった。

## Decision

親 Intent と子 Intent は**独立して claim 可能**。親を claim 中でも、別エージェントが子 Intent を claim できる。

## Rationale

- 親をロックすると子もロックする方式は粒度が荒すぎる
- 大きな親 Intent を「総括役」として長く保持しつつ、子は別担当に切り出すユースケースが自然に成立する
- 結果として「親はあえて claim しない」運用が定着するのを避けたい
- 木構造の利点を活かせる

## Consequences

- 親 claim 者と子 claim 者が同時に存在しうる
- 子 Intent への変更が親 Intent の整合性に影響する場合の調整は、エージェント間 or 人間に委ねる(プラットフォームは仲介しない)
- claim の継承や伝播は行わない
