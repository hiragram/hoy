# 0019. Intentのライフサイクルは active/closed + closing reason

- **Status**: Accepted
- **Related**: open-questions #3

## Context

Intent が陳腐化する原因(達成・放棄・ドリフト・誤り)に対処するため、Intent にライフサイクル状態を持たせるかを決める必要があった。

選択肢:
- (a) `active / completed / abandoned / archived` の多状態
- (b) ステータスは派生(配下Task完了状況などから算出)
- (c) `active / closed` の二値 + closing reason

## Decision

Intent は **`active / closed` の二値ステータス**を持つ。`closed` の場合のみ closing reason を併記する。

```
Intent.status: active | closed
Intent.closed_reason: completed | abandoned | superseded | obsolete  (status=closedのときのみ)
Intent.superseded_by: intent_id  (closed_reason=supersededのときのみ)
```

## Rationale

- 多状態(a)は状態遷移ルールが膨れ上がる
- 派生のみ(b)では「人間/エージェントが明示的に放棄する」操作が表現できない
- GitHub Issue の open/closed が長年機能している実績
- closing reason で陳腐化原因を区別でき、abandoned/obsolete/supersededを明示できる
- ADR 0008 の Intent 更新(version)とは別操作: update は内容の修正、close は意図そのものを終わらせる

## Decision詳細

### closing reason の意味

- `completed`: Intent の目的が達成された
- `abandoned`: 方針転換等で取りやめ
- `superseded`: 別 Intent に置き換わった(`superseded_by` で参照)
- `obsolete`: ドリフト等で前提が崩れた

### close と update の区別

- 内容を直したい → version を上げて update(active のまま)
- 別 Intent として作り直したい → 旧 Intent を `superseded` として close、新 Intent を作成

## Consequences

- closed な Intent は新規 claim を受け付けない(別途明文化が必要)
- closed な Intent 配下の Task の扱い(完了済みは保持、未完了は自動 close するか)は別途設計
- closed な Intent への依存(ADR 0018)を持つ Task は needs-review 相当のシグナルを受ける
- 「再オープン」操作の可否は別途検討。当面は closed → 新 Intent 作成、を推奨運用とする
