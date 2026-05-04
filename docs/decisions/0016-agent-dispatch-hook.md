# 0016. エージェント連携はリポジトリ内hookスクリプトで行う

- **Status**: Accepted
- **Related**: open-questions #2

## Context

hoy daemon が状態変化(Task差し戻し、claim強制release、Intent更新など)を検知したとき、エージェントへの通知・再開指示をどう行うかを決める必要があった。ADR 0002 によりプラットフォーム自身はエージェント機能を持たないため、エージェント起動の責務は外部に委ねる必要がある。

## Decision

リポジトリ内に **hookスクリプト**(例: `.hoy/hooks/agent-dispatch.sh`)を置けるようにする。daemon は状態変化時にこの hook を起動し、コンテキストを環境変数 + JSONペイロードファイルで渡す。エージェントの実起動・通知方法は hook の実装(プロジェクト側の責務)に委ねる。

## Rationale

- Git hooks の慣習を踏襲しており、開発者にとって馴染みやすい
- hoy はエージェント技術非依存(ADR 0002)を保てる
- プロジェクトごとに違うエージェント・オーケストレーション戦略を許容できる
- daemon がローカル常駐(ADR 0015)なので、hook も同一マシンで実行される単純なモデル

## Decision詳細

### hookに渡すコンテキスト

環境変数(スカラ):

```
HOY_EVENT             # task.rework_requested 等のイベント名
HOY_INTENT_ID
HOY_INTENT_VERSION
HOY_TASK_ID
HOY_AGENT_SESSION_ID  # 直前のclaim者(ある場合)
HOY_REASON            # イベント発生理由のコード
HOY_PAYLOAD_JSON      # 構造化データを格納した一時ファイルのパス
```

構造化データ(コンフリクト詳細、failしたcheck内容など)は環境変数ではなくJSONファイル経由。

### 標準イベント(初期セット)

- `task.rework_requested` - 統合失敗等で差し戻し
- `intent.updated` - claim中の親Intentが更新された
- `claim.revoked` - 強制releaseされた
- `verification.failed` - 検証経路がfail
- `task.assigned` - claim中Intent配下に新規Taskが追加された

### hookスクリプトの管理

- hook はリポジトリに含まれ、Intent/Taskと同じ意思決定の対象
- hook を変更する Task もガードレールを通す
- 実行されるhookは現在main相当の版を使う(claim時点で固定はしない)

## Consequences

- hoyはイベント定義・hook起動・コンテキスト受け渡しまで責任を持つ
- エージェントを実際に起動する処理(`claude code resume` や Slack通知 など)はプロジェクトの責任
- hookが書かれていないリポジトリでは、エージェントは「次に接続したときに状態変化を発見する」運用になる
- 環境変数命名規則(`HOY_*`)とイベント名はプロトコルの一部として固定
