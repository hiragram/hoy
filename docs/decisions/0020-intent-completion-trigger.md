# 0020. Intent完了は自動提案+明示承認

- **Status**: Accepted
- **Related**: open-questions #3

## Context

Intent を `closed (completed)` に遷移させるトリガーをどう設計するか。

選択肢:
- (a) 完全明示: 人間/エージェントの宣言が必須
- (b) 自動close: 配下の必須Task完了で自動遷移
- (c) 自動提案+承認: 必須Task完了で候補フラグ → 承認で確定

## Decision

**(c) 自動提案+明示承認**。

- 配下の必須(`required: true`)Task がすべて完了すると、Intent に「completion 候補」フラグが立つ
- claim 者 or 人間がこれを承認すると `closed (completed)` に遷移
- 承認なしには active のまま留まる

`abandoned / obsolete / superseded` は性質上、自動判定できないため必ず明示操作。

## Rationale

- ガードレール思想(ADR 0014)と整合: 自動でやれることはやる、ただし「Intent の目的が達成されたか」は意図の問題なので最終承認は残す
- 完全自動(b)は Task 完了 ≠ Intent 達成のケースを取りこぼす(検証経路に書ききれない要件があった場合等)
- 完全明示(a)は運用負荷が高く、エージェント運用で「Intent 閉じる」操作を毎回挟む手間がかさむ

## Consequences

- Intent に「completion候補」状態を表すフィールドが必要(暗黙的にTask状況から算出してもよい)
- 承認できる主体(claim者のみ・誰でも・親Intentのclaim者など)は別途検討
- 承認後の closed Intent への新規Task追加は不可とする想定(別途明文化が必要)
- 候補フラグが立った後に追加Taskが入って未完了になった場合、フラグは下りる
