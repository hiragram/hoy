# 0005. Intent更新時は子Taskにneeds-reviewフラグ

- **Status**: Accepted
- **Related**: open-questions #1, #3

## Context

エージェント or 人間が Intent A を読んで N 個の Task に分解した後、Intent A が更新された場合、既存 Task の扱いをどうするか。

選択肢:
1. 自動で無効化する
2. リンクは残るが needs-review フラグを立てる
3. 何もしない(乖離する)

## Decision

Intent が更新された場合、その Intent に紐づく Task に **needs-review フラグ**を立てる。Task は自動無効化されず、人間/エージェントによる確認後にフラグを下ろす。

## Rationale

- 自動無効化は厳しすぎる(エージェントが再分解する手間が常に発生)
- 何もしないは乖離が静かに進む(open-questions #3 の意図陳腐化問題と直結)
- needs-review はその中間で、人間/エージェントに「見直すべき」シグナルを出しつつ、判断は委ねる

## Consequences

- Task に `needs_review: bool` または `review_reason: enum` 相当のフィールドが必要
- フラグを立てる契機(Intent のどの版から派生した Task か)を判定するため、ADR 0008 の Intent バージョンと連動する
- needs-review フラグの解除フロー(誰が・どう確認したら下ろせるか)は別途設計が必要
