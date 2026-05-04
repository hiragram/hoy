# 0009. Intentは1エージェントによる排他claimで管理する

- **Status**: Accepted
- **Related**: open-questions #2

## Context

並列エージェントの調停モデル(レベル3: 同じ Intent を複数エージェントが扱う問題)への対応として、claim/lock の方式を決める必要があった。

選択肢:
- (a) 排他ロック: 1エージェントが claim 中、他は待つ
- (b) 並列作業 + 後で統合: 複数案を保持して最後に選ぶ
- (c) ハイブリッド: 分解は並列、実装は排他

## Decision

Intent に対する作業権は **1エージェントによる排他 claim** で管理する。hoy は claim/release/lock の管理までを責務とし、claim したエージェントが配下の Task をどう処理するか(サブエージェント委譲など)は関知しない。

## Rationale

- 責務の境界がクリーン: プラットフォームは「誰の仕事か」を保証、エージェント側は内部の並列化戦略を自由に選べる
- ADR 0002(プラットフォームはエージェント機能を持たない)と整合
- 複数案保持(b)はストレージと統合の複雑さに対するリターンが小さい
- ハイブリッド(c)は実装が複雑で、最初に入れる価値が薄い

## Consequences

- Intent ごとに `claimed_by: agent_session_id | null` の状態を持つ
- claim/release は API として明示
- 他のエージェントが同じ Intent に介入したい場合、claim 解放を待つか、別 Intent として切り出す必要がある
