# hoy

A development platform redesigned for the agent era.

GitHub assumes humans write the code, humans review it, and humans merge it. That assumption is now in the way: agents write a hundred files in a minute, but the workflow around them — pull requests, review comments marked "resolved", a branch model designed for a few human committers — was never built for that. `hoy` is an attempt at the alternative.

> **Status:** Pre-alpha, single-developer MVP. Data model and protocol are stable enough to dogfood on; the integration story (parallel claims, conflict rebase, event subscriptions) is not yet exercised. Expect breakage.

## What it does differently

| | GitHub | hoy |
|---|---|---|
| Center of gravity | code + human comments | **Intent / Task / Verification / Claim** |
| Review | humans read diffs | automated checks gate completion; humans approve only what truly needs them |
| Review comments | unstructured threads | structured tickets with status and resolving commit |
| Concurrency | branches that humans name | per-Intent claims, exclusive per Principal, with heartbeat |
| Integration | manual merge after PR | task completion *is* the integration |
| Undo | `git revert` | first-class `task.revert` state transition |
| `git` | a tool humans drive | a daemon-internal implementation detail |
| Surface | UI first, API bolted on later | API/protocol first; CLI and MCP are thin wrappers |

The longer version of the philosophy lives in [`docs/concept.md`](docs/concept.md). Individual design decisions are in [`docs/decisions/`](docs/decisions/) (ADRs).

## Architecture

```
                 ┌─────────────┐         ┌─────────────┐
                 │  hoy CLI    │         │  hoy mcp    │  (stdio for agents)
                 └──────┬──────┘         └──────┬──────┘
                        │ JSON-RPC 2.0 over Unix domain socket
                        ▼                       ▼
                 ┌──────────────────────────────────────┐
                 │             hoy daemon               │
                 │   (Dispatcher, hooks, claim purge)   │
                 └──────────────────────────────────────┘
                        │
                ┌───────┴────────┐
                ▼                ▼
          ┌──────────┐     ┌────────────┐
          │ SQLite   │     │ git (repo) │
          │ state.db │     │            │
          └──────────┘     └────────────┘
```

Modules (see [ADR 0040](docs/decisions/0040-module-structure.md)):

- **HoyCore** — domain types, repositories, services, git wrapper. No transport.
- **HoyProtocol** — JSON-RPC envelopes, method definitions, DTOs, events. Depends on nothing.
- **HoyDaemon** — Unix socket listener, request dispatcher, DTO conversion, background jobs.
- **HoyCLI** — `hoy` subcommands built on `swift-argument-parser`, talking to the daemon over the socket.
- **HoyMCP** — stdio MCP server that exposes hoy methods as tools and forwards calls to the daemon.

## Build

Requires Swift 6.0+ (Apple toolchain). macOS is the primary platform; Linux is best-effort.

```sh
swift build
swift test
```

The binary is produced at `.build/debug/hoy` (or `.build/release/hoy` with `swift build -c release`).

### Or run via swx (no clone needed)

[swx](https://github.com/hiragram/swx) is npx for Swift packages. With it you can run any version of `hoy` straight from GitHub:

```sh
# Install swx once
curl -fsSL https://raw.githubusercontent.com/hiragram/swx/main/install.sh | bash

# Run hoy
swx hiragram/hoy -- --version
swx hiragram/hoy -- daemon start --root ~/.hoy/hoy-dev
swx hiragram/hoy -- status --root ~/.hoy/hoy-dev --watch
```

The first invocation builds the package (~30s); subsequent runs use the cached binary at `~/.swx/cache/hiragram/hoy/main/`.

## Quick start

```sh
# Pick a workspace root. Every subcommand respects HOY_ROOT / HOY_SOCKET, so
# exporting them once means you don't repeat --root / --socket on each call.
export HOY_ROOT=/tmp/hoy-demo

# Start the daemon in the foreground
hoy daemon start &

# Create an Intent and a Task underneath it
INTENT=$(hoy intent create "ship MVP" --json | jq -r .id)
TASK=$(hoy task create --intent "$INTENT" "wire the dispatcher" --json | jq -r .id)

# Add an automated verification check
hoy verification add "$TASK" --kind automated --category unittest --spec "swift test"

# Run the automated checks (records exit/stdout/stderr as evidence)
hoy verification run "$TASK"

# Complete the task — commits the working tree, transitions the task,
#   and writes an audit entry. A `task.completed` hook fires if you've
#   put a script at $HOY_ROOT/hooks/task.completed.sh.
hoy task complete "$TASK"

# Stop the daemon
hoy daemon stop
```

The same surface is available via MCP for agents:

```sh
hoy mcp <<<'{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## Layout under `$HOY_ROOT`

```
<root>/
  state.db        SQLite metadata (Intents, Tasks, Verifications, Claims, Audit log)
  repo/           git working tree (the *contents* hoy is tracking)
  socket          Unix domain socket (mode 0600)
  daemon.pid      Foreground daemon's pid (used by `hoy daemon stop`)
  daemon.log      Per-request trace log
  hooks/<event>.sh   Optional shell hooks invoked with JSON payload on stdin
```

## Subcommands

| Command | Purpose |
|---|---|
| `hoy daemon start \| stop \| status` | Lifecycle of the local daemon |
| `hoy intent create \| get \| list \| update \| close` | Intent CRUD |
| `hoy task create \| get \| list \| complete \| revert` | Task CRUD and lifecycle |
| `hoy verification add \| run \| report \| waive` | Manage Verification checks |
| `hoy claim acquire \| release \| heartbeat` | Per-Intent exclusive work claims |
| `hoy reconcile` | Detect drift between SQLite and git |
| `hoy backup <dir>` / `hoy restore <snapshot>` | Snapshot of `state.db` + `repo/` |
| `hoy auth login \| logout \| whoami` | Issue/revoke a session token (ADR 0025) |
| `hoy events subscribe` | Stream daemon events (`task.completed` etc.) over the socket |
| `hoy status [--watch]` | Tree view of intents, tasks and active claims; `--watch` redraws on events |
| `hoy mcp` | Run as an MCP stdio server, bridging to the daemon |

Every subcommand follows a consistent argument convention (see [ADR 0043](docs/decisions/0043-cli-argument-convention.md)):

- The **primary entity ID** the command operates on is positional: `hoy intent get <id>`, `hoy task complete <id>`, `hoy verification add <taskId> ...`.
- **Secondary references** (parent, foreign keys) are `--flag`s: `hoy task create --intent <id> <title>`.
- **Content** (titles, reasons, specs) is `--flag` unless it is short and required, in which case it can be the trailing positional.
- All output-producing commands accept `--json` for machine-readable output.
- All commands respect `--root` / `--socket` (or the `HOY_ROOT` / `HOY_SOCKET` environment variables).

## Project conventions

- **Language for design conversations, ADRs, commit messages: Japanese.** Conventional Commits keywords stay English (see [`CLAUDE.md`](CLAUDE.md)).
- **TDD, t-wada style.** Red → Green → Refactor, one test at a time. Tests use [Swift Testing](https://developer.apple.com/documentation/testing) per [ADR 0042](docs/decisions/0042-test-framework-swift-testing.md), not XCTest.
- **Every design judgment becomes an ADR** under `docs/decisions/`, indexed in [`docs/decisions/README.md`](docs/decisions/README.md). Existing ADRs are not edited in place; they are superseded.
- **MVP scope is tracked in [`docs/mvp-todo.md`](docs/mvp-todo.md).** Done items are marked `[x]`; deferred items carry a note explaining why.

## What's not built yet

Tracked in `docs/mvp-todo.md`. The notable gaps:

- Conflict resolution: automatic rebase + verification re-run on integration conflicts ([ADR 0017](docs/decisions/0017-conflict-resolution.md)). Needs the parallel-claim use case to be exercised first.
- ~~Token-based authentication and session establishment ([ADR 0025](docs/decisions/0025-principal-session-model.md)).~~ ✅ Implemented. Run `hoy auth login --principal-id <id> --display-name "..."` to issue a session token; subsequent CLI/MCP calls authenticate as that Principal. Without a token the daemon falls back to its `--principal-id` default for local convenience.
- ~~Event push (subscription channel for `task.completed`, `claim.expired`, `conflict.detected`).~~ ✅ Implemented for `task.completed` and `task.reverted` via `hoy events subscribe`. `claim.expired` and `conflict.detected` will be added once the parallel-claim conflict path is built.
- Multi-developer mode is explicitly out of scope for the MVP ([ADR 0029](docs/decisions/0029-mvp-single-developer.md)).

## License

TBD ([ADR 0030](docs/decisions/0030-fully-open-source.md) commits to fully OSS; specific license is open).
