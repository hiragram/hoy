# 0043. CLI 引数体系の規範

- **Status**: Accepted
- **Related**: ADR 0007

## Context

dogfooding 初日に CLI の引数体系が一貫していないことが発覚した。

- `hoy intent get <id>` は positional
- `hoy verification add --task <id> --kind <kind>` は全 flag
- `hoy task create --intent <id> <title>` は混在

これは「primary に何を据えるか」がコマンドごとに揺れているためで、人間にもエージェントにも辛い。

## Decision

以下の規範を採用する。

### 1. Primary entity ID は positional

そのコマンドが「何を操作するか」を表す ID は最初の positional 引数として受ける。`<noun> <verb>` のとき `verb` の対象がそれに当たる。

| 例 | primary |
|---|---|
| `hoy intent get <id>` | Intent |
| `hoy task complete <id>` | Task |
| `hoy claim acquire <intentId>` | Intent |
| `hoy verification add <taskId> ...` | (検証経路の所属する) Task |
| `hoy verification run <taskId>` | Task |

### 2. Secondary な参照は `--flag`

コマンドの主体ではないが必要な参照(親、所属先など)は `--flag` で渡す。

- `hoy task create --intent <id> <title>`(主体は新 Task、`--intent` は所属参照)
- `hoy verification report <taskId> --check <checkId> --passed`

### 3. Content (title / body / reason / spec) は

- 短く必須なら positional の最後に: `hoy intent create <title>`
- 複数 / オプショナル / 多行は `--flag`: `--body`, `--reason`, `--spec`

### 4. すべての主要 subcommand は `--json` をサポートする

stdout に印字するすべての subcommand は `--json` を受け、JSON 形式の機械可読出力に切り替える。エージェントが安定して扱える表現を必ず提供する。

### 5. `--root` / `--socket` はワークスペース指定の共通オプション

全 subcommand が `GlobalOptions` 経由で受ける。環境変数 `HOY_ROOT` / `HOY_SOCKET` でも上書き可能。

## Rationale

- 人間がドキュメントを見ずに型を推測できる規則性が要る
- LLM クライアントから安定して呼び出せるよう、機械可読モード (`--json`) は必ず一級
- 「主体は positional、参照は flag」は git や kubectl など主要 CLI の慣行と整合する

## Consequences

- 既存 CLI の `verification` 系を positional taskId に移行する破壊的変更を伴う
- すべての subcommand に対し `--json` 経路を保証するためのテストが必要(将来追加)
- ドキュメント/README はこの規範を前提に書く
