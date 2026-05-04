# 0047. Task の粒度は「1 worktree = 1 commit」を目安にする

- **Status**: Accepted
- **Related**: ADR 0001, ADR 0045

## Context

dogfooding (wordle) で Intent を作成した際、UI Intent 配下に Task を 5 つ
切っていた:

- 6x5 盤面の描画
- 推測入力 + 送信
- セル色反映
- 勝敗 / リプレイ
- モバイル幅

これらは別々の関心事だが、実装上は 1 つの `index.html / styles.css /
main.js` に集約される。1 task ずつ worktree を切って commit すると、
4 つは「前 task のコードが既に main にあるから commit が空 → エラー」
または「metadata-only で完了」する状態になり、task tree とコミット履歴が
一致しなくなった。

## Decision

**Task は「1 つの worktree に収まり、1 つの commit で完結する変更」
を目安に切る**。

具体的には:

- 同じファイル群を編集する作業は 1 task に統合する
- task は完了時に意味のある diff を main に追加すべき。空コミットを
  生む task は粒度が細かすぎる
- 「ある機能の subset」のような分け方ではなく、「独立して merge できる
  変更」で分ける
- 設計判断や調査など commit に紐付かない作業は `--no-commit` (metadata
  完了) で扱う。これは task として正当だが、実装 task と混ぜない

## Rationale

- ADR 0045 の per-task worktree モデルは「1 task = 1 worktree = 1 branch
  = (理想的に) 1 commit」を前提に組まれている。粒度が細かすぎると
  worktree を切る回数だけ増えてオーバヘッドになる
- 細かい subgoal を追跡したい場合は task のチェックリスト (body 内)、
  または verification check で表現するほうが自然
- Intent の方が「意味的な機能単位」を担うので、機能を細かく切りたいなら
  Intent を増やす(子 Intent)。task は変更単位

## アンチパターン

- 1 つのファイルを 5 ヶ所編集する変更を 5 task にする → 1 task で OK
- 「テストを書く」「実装する」「ドキュメントを書く」を 3 task に分ける →
  通常 1 task で完結する。verification check で別々に表現可能
- UI のリファクタを「ヘッダ」「フッタ」「サイドバー」のコンポーネント別
  3 task に分ける → 同じ commit で済むなら 1 task

## ガイドライン (推奨)

- task を切る前に「これは別 commit にしたいか」を自問する。Yes なら
  task、No なら同 task の 1 部分として扱う
- Intent の body に作業の概要を書き、task の数は最小限にする (実装着手
  時に必要なら追加)
- 1 つの Intent 配下に大量の task が並ぶときは「Intent 自体が機能を
  抱え込みすぎ」のサイン。子 Intent への分割を検討

## Consequences

- 既存の wordle dogfooding で生まれた task の多くが metadata-only 完了に
  なったのは本 ADR の通り。今後は同じ粒度で task を切らない
- Intent / Task の意味付けがより明確に: Intent = 機能, Task = 変更
- mvp-todo.md のような「フェーズ計画」は必ずしも 1 task 単位の粒度では
  ない。計画と task は別レイヤ
