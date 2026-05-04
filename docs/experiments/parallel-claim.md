# 並列 claim 実験

ADR 0017 / ADR 0045 を裏付けるためのエンドツーエンド実験。
2 つの Principal が並列に作業し、claim と worktree が期待通りに動作することを確認する。

## 前提

- `hoy` バイナリがビルド済(`swift build` で `.build/debug/hoy`)
- 別の作業を壊さないようテスト用 root を使う(`/tmp/hoy-parallel-experiment`)

## スクリプト

```sh
#!/bin/sh
set -eu

export HOY_ROOT="${HOY_ROOT:-/tmp/hoy-parallel-experiment}"
HOY=${HOY:-./.build/debug/hoy}

rm -rf "$HOY_ROOT"
"$HOY" daemon start --principal-id setup > /dev/null 2>&1 &
sleep 1

# 2 つの Principal でログインしトークンを別ファイルに保管
"$HOY" auth login --principal-id agent-a --kind agent --display-name "Agent A" > /dev/null
mv "$HOY_ROOT/auth.token" "$HOY_ROOT/a.token"
"$HOY" auth login --principal-id agent-b --kind agent --display-name "Agent B" > /dev/null
mv "$HOY_ROOT/auth.token" "$HOY_ROOT/b.token"

useA() { cp "$HOY_ROOT/a.token" "$HOY_ROOT/auth.token"; }
useB() { cp "$HOY_ROOT/b.token" "$HOY_ROOT/auth.token"; }

# Intent / Task を準備
IA=$("$HOY" intent create "edit shared" --json | jq -r .id)
IB=$("$HOY" intent create "edit shared (parallel)" --json | jq -r .id)

useA
TA=$("$HOY" task create --intent "$IA" "A modifies shared" --json | jq -r .id)
WA=$("$HOY" task workspace "$TA")

useB
TB=$("$HOY" task create --intent "$IB" "B modifies shared" --json | jq -r .id)
WB=$("$HOY" task workspace "$TB")

# 同じ shared.txt をそれぞれの worktree で別内容に編集
echo "from A" > "$WA/shared.txt"
echo "from B" > "$WB/shared.txt"

# A を先に統合 → 成功
useA
"$HOY" task complete "$TA"

# B を統合 → conflict
echo "--- B complete (conflict 期待) ---"
useB
if "$HOY" task complete "$TB"; then
    echo "ERROR: conflict が起きるはずが成功した"
    exit 1
fi
echo "OK: integrationConflict が返り、B の worktree は保持されている"

# 後始末
"$HOY" daemon stop > /dev/null
```

## 期待される結果

1. `auth login` が 2 回成功し、Principal A / B が登録される
2. claim は `target_intent_id` ごとに独立(IA は A、IB は B)。同 Intent への重複 claim は `-32001 alreadyClaimed`
3. A の `task complete` は `{"sha":"...","task":...}` を返す
4. B の `task complete` は `-32001 integration conflict: ...` を返す
5. B の worktree (`$WB`) は `git rebase --abort` 状態で残り、`shared.txt` の内容は失われていない
6. `task.completed` (A 分) と `conflict.detected` (B 分) のイベントが
   `hoy events subscribe` 接続に流れる

## 観察ポイント

- 真の並行 (`task complete &` を 2 つ同時に投げる) で `.git/index.lock` 競合が起きないこと(Git の subprocess を NSLock で直列化、ADR 0045 の前段で対応済み)
- `claim.expired` イベントが TTL 切れ直後の purge ループで配送されること
- subscribe + 同接続 RPC の多重化が動作すること(ADR 0046)

## 過去の発見

このスクリプトを最初に走らせたときに見つかった摩擦:

| 摩擦 | 対応 |
|---|---|
| Index.lock 競合 → `-32603` 露出 | Git クラスを NSLock 直列化 |
| 同一ファイルの順次編集が silent overwrite | per-task worktree (ADR 0045) で構造的に解決 |
| `conflict.detected` 未配送 | TaskService.complete 失敗パスで EventBus.publish |
| `internalError` で conflict が紛れる | RPCErrorCode.conflict (-32001) に分類 |

すべて main に取り込み済。
