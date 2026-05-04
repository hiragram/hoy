# 0018. Task間の依存はIntentの特定versionへの参照で表現する

- **Status**: Accepted
- **Related**: open-questions #2

## Context

Intent をまたいだ Task 依存をどう表現するか。例: Intent X の Task「決済API追加」と、Intent Y の Task「決済API を呼ぶ UI追加」。後者は前者の成果物に依存する。

選択肢:
- (a) Task→Task の依存
- (b) Task→Intent の依存
- (c) 両方許容
- (d) 形式化しない

## Decision

**Task は Intent の特定 version (`intent_id@vN`) への依存を宣言できる**。Task→Task の依存は持たない。

```
Task.depends_on: [intent_id@vN, ...]
```

## Rationale

- ADR 0009 で「Intent が claim/作業の単位」と決めた。依存もこの粒度に揃えるのが思想的に整合
- Task は Intent 内部の都合で分割・統合・差し戻しされうるが、Intent ID は安定(ADR 0008)
- 「Intent X v3 で約束されている契約に依存している」と version を明示することで、依存先 Intent が更新された場合の影響を検出できる
- Task→Task 依存は粒度が細かすぎ、依存先 Task の再構成に弱い

## Decision詳細

### 依存解決のセマンティクス

`intent_id@vN` への依存が**満たされる条件**: Intent X の version vN 時点で必須(`required: true`)とされていた全 Task が完了し統合されていること。

### Intent が更新されたときの挙動

依存先 Intent X が v3 から v4 に更新された場合:

- 依存元 Task の依存は **`intent_id@v3` のまま**(自動で v4 に追従しない)
- 依存元 Task に **needs-review 相当のフラグ**を立てる(ADR 0005 と同じ機構)
- 担当エージェント/人間が「v4 でも依存が成立するか」を確認して、依存を v4 に更新するか、契約変化に合わせて実装を直すかを判断

### 依存先が claim 中・未着手の場合

依存元 Task は「依存待ち」状態として保持される。実装に着手できないことを daemon が把握しておくことで、誤って claim → 即詰まる、という事故を減らせる。

## Consequences

- Task に `depends_on: [intent_ref]` フィールドが必要
- Intent ref は `intent_id@vN` 形式(ADR 0008 のバージョン管理に依拠)
- 依存待ち状態の Task は claim できるが実装は進められない、という運用が成立する(細部は別途設計)
- 同一 Intent 内の Task 間順序は本ADRでは扱わない(必要なら別途検討、当面はエージェント側で順序付け)
- 循環依存の検出が必要(Intent 木構造とは別の依存グラフが発生するため)
