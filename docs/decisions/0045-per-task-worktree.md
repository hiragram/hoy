# 0045. Task ごとに git worktree を切り、完了時に rebase で統合する

- **Status**: Proposed
- **Related**: ADR 0013, ADR 0014, ADR 0017, ADR 0034

## Context

並列 claim 実験 (dogfooding 第3ラウンド) で次のことが具体化した:

1. 異なる Intent / 異なるファイルの並行作業は問題なく動く
2. 同じファイルを A→B 順次に編集すると **silent overwrite** が起きる。テキスト conflict はないが意味 conflict が発生し、A の作業が B の commit で上書きされても警告が出ない
3. 真に並行する `task.complete` は `.git/index.lock` 競合で失敗していた(Git の subprocess 直列化で対応済)

(2) は現在の「daemon が単一の作業ツリー (`<root>/repo`) を全 task で共有する」モデルの帰結である。task は独立した空間で作業していると思っていても、実体としては同じディスク上のファイルを順番に上書きしているにすぎない。

ADR 0017 はコンフリクト時の自動 rebase + 検証経路再走を要請しているが、単一作業ツリーではそもそもコンフリクトが発生しない (片方が必ず後勝ちする)。意味のある rebase 路を作るためには、各 task が独立したブランチで作業している必要がある。

## Decision

**Task ごとに独立した git worktree とブランチを切る**。

```
<root>/repo/                # 主ワークツリー (= main ブランチ)
<root>/worktrees/<taskId>/  # task 専用 worktree
```

- task 作成時に `git worktree add <root>/worktrees/<taskId> -b task/<taskId> <main の先頭>` を行う
- task は自身の worktree でファイル編集する
- `task.complete` の流れ:
  1. `git -C worktrees/<taskId> rebase main` で main の最新を取り込む
  2. rebase が成功したら、main を `task/<taskId>` の先頭に fast-forward
  3. worktree とブランチを削除
  4. `task.completed` イベント発火
- rebase が失敗したら:
  1. `git rebase --abort` で worktree を rebase 直前に戻す
  2. `task` の status は `claimed`/`inProgress` のまま
  3. `conflict.detected` イベントを発火、ペイロードに rebase 失敗 paths を含める
  4. agent (または人間) が worktree でコンフリクト解消、再度 `task.complete` を呼ぶ

## Rationale

- **silent overwrite が構造的に起きなくなる**: A と B が別ブランチで作業しているので、main へ統合する瞬間に必ず rebase を経由する。同じ行を触っていれば conflict が顕在化し、ADR 0017 の通り自動 rebase + 検証経路再走 + 失敗時 hook で agent に差し戻せる
- **claim 排他とスコープが揃う**: 1 task = 1 worktree = 1 branch という対応が綺麗。claim は target Intent の worktree への書き込み権利を意味する一級概念になる
- **concept §6.2 のメンタルモデルと整合**: 「ブランチは人間が命名・管理しない」「コンフリクトは自動 rebase + 失敗時 hook」という記述は worktree 切り出しを暗黙に前提していた。これを明示する
- **revert の挙動が綺麗になる**: revert は main の commit を `git revert` する操作のまま。完了済 task の commit はその時点で main に統合された後の sha なので、revert の対象は安定する

## 代替案と却下理由

### (a) 単一 worktree のまま、影響ファイル一覧で警告

各 task に「触ったファイル」を記録、claim 解放時か Intent close 時に重なりを警告する。

- 利点: 実装が軽い
- 欠点: silent overwrite の根本解決にならない (警告は事後的)。ADR 0017 の自動 rebase が不可能のまま

### (b) 全 task をシリアル化 (グローバルロック)

claim を持つ task しか作業ツリーを書き換えられないようにする。

- 利点: 並行性が単純
- 欠点: 並行作業の利点を失う。エージェント時代に並列 100 task の前提と矛盾

### (c) 主作業ツリーを使い回し、commit ごとに main を進める

現状の挙動をそのまま並列に。

- 利点: 現状維持
- 欠点: dogfooding 第3ラウンドで silent overwrite が確認済み。採用不可

## Consequences

### 良い影響

- ADR 0017 の自動 rebase / conflict.detected 実装が初めて意味を持つ
- task の作業空間が物理的に分離され、並列度を上げても安全
- agent ごとに異なる worktree を見るので、エージェントの作業ディレクトリ管理がシンプル

### 悪い影響 / 注意点

- **ディスク使用量が増える**: worktree ごとに作業ツリーのコピーが必要。git の worktree 機能は `.git/worktrees/<id>/` に index 等を持つだけで、作業ファイルは生のコピー。MVP の 1 開発者スコープなら問題ないが、将来は cleanup ポリシーが必要
- **再ビルド/再テストの観点**: 別 worktree でビルドキャッシュが分かれる。Swift/Xcode 等のキャッシュは worktree ごとに発生。検証経路の automated check の実行時間が増える可能性
- **task 作成時に main の先頭を固定する**: claim 時点で worktree を切るので、その時点の main の先頭がベースになる。後から main が進んだら rebase が必要(本 ADR の通り task.complete 時に行う)
- **失敗状態の管理**: rebase が失敗した worktree は agent に渡される。完了/中止のどちらかに到達するまで disk 上に残る。タイムアウト/明示 abort の API が必要
- **既存の TaskService.complete を再設計**: `git add -A && git commit` ではなく、worktree 内で「すでにコミット済の状態」を main に rebase + ff の流れに変わる。`completedSha` のセマンティクスは「main に統合された後の sha」のまま

## 実装段階

本 ADR の採用時点では未実装。`docs/mvp-todo.md` に該当タスクが既にある (Conflict resolution Intent 配下の "task ごとに git worktree を切り、task.complete でメインへ rebase する設計に進化させる")。実装は段階的に:

1. `WorktreeManager` を HoyCore に導入(`add` / `remove` / `rebaseOnto`)
2. 既存 `TaskService.complete` を worktree 経由に書き換え
3. rebase 失敗時の `conflict.detected` イベント発火
4. CLI: `hoy task workspace <id>` で task の worktree path を返す(agent が `cd` できるように)
5. agent-dispatch hook の payload に worktree path を載せる(agent 起動時に作業場所を渡せる)

### MVP との関係

ADR 0031 の MVP スコープには「Task 完了時の即時統合」が含まれており、worktree モデルへの移行はその実装詳細に過ぎない。MVP 期間中に置き換える前提とする。

## 関連する未決事項

- worktree 削除のタイミング(完了直後 / 一定期間保持 / agent が明示)
- 検証経路 (automated check) を worktree 内で走らせるべきか(現状は `<root>/repo` で走る)。ビルドキャッシュ問題と関連
- `hoy task workspace <id>` API の正式名
- worktree の disk usage モニタリング(将来の reclaim ジョブ)
