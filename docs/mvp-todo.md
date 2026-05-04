# MVP 開発 TODO

ADR 0031 の MVP 必須項目を実装順に並べたチェックリスト。
依存関係を意識した段階構成。各段階は前段階の上に積む。

進め方:
- 各項目は TDD t-wada スタイル(Red→Green→Refactor)で進める
- テストは Swift Testing(ADR 0042)で書く
- 段階内の項目は基本上から、依存があれば前後する
- 完了したら `[x]` に更新し、関連 ADR や補足を必要に応じて追記
- 進める中で発覚した未決事項は `docs/open-questions.md` または新 ADR に切り出す

---

## Phase 0: 足場(完了)

- [x] Swift Package 初期化(ADR 0040 の 5 モジュール構成)
- [x] SQLite.swift 依存追加(ADR 0041)
- [x] CI なしでもローカルで `swift test` が通る状態

---

## Phase 1: ドメインモデル(永続化なし、純粋値型)

ストレージや I/O を一切持たない、メモリ上の値型として最初に固める。
TDD で型の振る舞いを確定させてからストレージに乗せる。

### 1.1 Intent

- [x] `Intent.create(title:)` が安定IDを採番(三角測量で UUID へ追い込む)
- [x] `version` は 1 で生まれる(ADR 0008)
- [x] `title` / `body` を保持
- [x] `status` は `active` で生まれる(ADR 0019)
- [x] `parentId: IntentID?` を持てる(ADR 0004、入れ子)
- [x] `update(title:body:)` で新しい version を返す(ADR 0008、ID は安定)
- [x] `close(reason:)` で `closed` に遷移、closing reason 必須(ADR 0019)
- [x] `closed` から `active` への遷移は禁止(ADR 0023)

### 1.2 Task

- [x] `Task.create(intentId:title:)` で安定 ID
- [x] 必ず `intentId` を持つ(ADR 0001)
- [x] `createdBy: PrincipalRef` を保持(ADR 0006)
- [x] `status`: `open / claimed / in_progress / completed / reverted / closed`(型として定義済、遷移は順次実装)
- [x] `depends_on: [IntentRef@version]` を保持(ADR 0018)
- [x] `completed → reverted` 遷移を一級操作で持つ(ADR 0034)
- [ ] Intent close 時に未完了 Task は cascade close(ADR 0024)(サービス層で実装)

### 1.3 VerificationCheck

- [x] `kind: automated | human` と `category: String` を持つ(concept §5.4)
- [x] `status: pending | running | passed | failed | waived`
- [x] `required: Bool`
- [x] `evidence` フィールド(任意の構造化データ)
- [x] Task は `[VerificationCheck]` を持つ
- [x] 完了判定: 必須 check がすべて `passed` か `waived`
- [x] `waived` 状態には理由と承認者が必須

### 1.4 Claim

- [x] `Claim(principalId, targetIntentId, expiresAt)` 値型
- [ ] Intent 単位で 1 Principal が排他(ADR 0009)(Phase 3.1 ClaimRegistry で実装)
- [ ] 親と子は独立に claim 可能(ADR 0010)(Phase 3.1 ClaimRegistry で実装)
- [ ] 書き込み排他、読み取り自由(ADR 0012)(Phase 3.1 ClaimRegistry で実装)

### 1.5 Principal / Session

- [x] `Principal` 値型(ADR 0025)
- [x] `Session` は Principal に紐づく、token 持ち
- [x] 1 Principal が複数 Session を持てる

### 1.6 AuditEntry

- [x] `AuditEntry` 値型: `timestamp / actor / op / payload`(ADR 0027)
- [x] append-only な性質を型レベルで担保(mutating な操作を生やさない)

---

## Phase 2: ストレージ層(SQLite + Git)

### 2.1 SQLite

- [x] `state.db` の配置場所を決定(`<root>/state.db`、Workspace.open で確定)
- [x] スキーマ定義(Intent / Task / Verification / Claim / Audit / Principal / Session)
- [x] マイグレーション仕組み(version テーブル + 起動時適用)
- [x] WAL モード有効化
- [x] Repository(Intent / Task / Claim / Principal / Session / AuditLog 各エンティティ用に実装)
- [x] AuditLog は INSERT のみ、UPDATE/DELETE をトリガーで拒否(ADR 0027)

### 2.2 Git ストレージ

- [x] daemon 内部リポジトリの初期化(Git.initIfNeeded)
- [x] `git` subprocess 実行ラッパー(ADR 0036、stdout/stderr/exit を構造化)
- [x] Task 完了時のコミット作成(Git.commitAll、ADR 0014)
- [x] revert 操作(Git.revert、ADR 0034)
- [x] rebase 操作(Git.rebase / rebaseAbort、ADR 0017)

### 2.3 統合 Repository

- [x] Workspace 集約(Storage / Git / 各 Repository)
- [x] Task 完了時の Git commit 連携(TaskService.complete)
- [ ] トランザクション境界の設計(SQLite tx と git 操作のクラッシュ整合、reconciliation で対応予定)

---

## Phase 3: ドメインサービス

### 3.1 Claim 管理

- [x] claim 取得 API(ClaimRepository.acquire、競合時 alreadyClaimed)
- [x] ハートビート受信と更新(ClaimRepository.heartbeat、ADR 0011)
- [x] 期限切れ claim の強制 release(ClaimRepository.purgeExpired、daemon タイマー連携は Phase 5.3)

### 3.2 統合(Integration)

- [x] Task 完了時に main へ即時統合(TaskService.complete、ADR 0014)
- [x] revert 操作(TaskService.revert、ADR 0034)
- [ ] コンフリクト時の自動 rebase(ADR 0017、並列 claim が動き出してから実装)
- [ ] rebase 失敗時の差し戻し(エージェントへのイベント通知、Phase 5.2 dispatch と連動)
- [ ] 統合後の必須検証経路再走(ADR 0017)

### 3.3 検証経路実行

- [x] automated check の実行(VerificationRunner.runAutomated、subprocess)
- [x] 結果(stdout/stderr/exit)を evidence として保存
- [x] human check の status 遷移 API(recordHumanResult / waive)
- [ ] 並列実行ポリシー(open-questions #7、MVP は逐次)

---

## Phase 4: プロトコル定義(JSON-RPC)

### 4.1 メソッド定義(HoyProtocol)

- [x] `intent.create / get / list / update / close`
- [x] `task.create / get / list / complete / revert`(claim は claim.* で対応)
- [x] `verification.add / run / report / waive`
- [x] `claim.acquire / release / heartbeat`
- [ ] `audit.append`(daemon 内部用、外部 RPC では露出させない)
- [x] エラーコード体系(RPCErrorCode、JSON-RPC 標準 + hoy 固有 -32000 番台)
- [x] バージョン情報の advertising(HoyProtocolVersion.current)

### 4.2 イベント定義

- [x] イベントスキーマ(EventEnvelope、ADR 0016)
- [x] `task.completed / verification.failed / claim.expired` を初期定義
- [ ] `conflict.detected`(統合コンフリクトを実装する Phase 3.2 の続きで追加)
- [ ] サブスクリプション機構(daemon 接続上での push、Phase 5.2)

---

## Phase 5: daemon

### 5.1 ソケット listen

- [x] Unix domain socket 初期化(UnixSocketServer、`0600` 権限、ADR 0039)
- [ ] 接続受付と Session 確立(Phase 5.1 後半: TokenAuthenticator)
- [ ] Principal 認証(token、ADR 0025)
- [x] graceful shutdown(stop)

### 5.2 リクエスト dispatch

- [x] JSON-RPC 2.0 のパース・バリデーション(Dispatcher)
- [x] HoyProtocol メソッドを HoyCore に dispatch(intent/task/verification/claim)
- [x] エラー応答の整備(parseError / methodNotFound / invalidParams / notFound / conflict / invalidState)
- [ ] リクエストごとのトレースログ
- [ ] イベント push (task.completed 等の subscription)

### 5.3 バックグラウンドジョブ

- [ ] claim ハートビート期限切れ監視(タイマーで purgeExpired を回す)
- [ ] 検証経路実行ワーカー(現状は同期実行、将来は非同期化)
- [ ] hook 起動(ADR 0016 の agent-dispatch.sh)

---

## Phase 6: クライアント

### 6.1 CLI

- [x] `hoy daemon start`(フォアグラウンド)
- [ ] `hoy daemon stop / status`(常駐管理は Phase 7 と合わせて)
- [x] `hoy intent create / get / update / close`(list は次)
- [x] `hoy task create / get / complete / revert`(list は次)
- [x] `hoy verification run / report / waive`(add は次)
- [x] `hoy claim acquire / release / heartbeat`
- [x] `intent list` / `task list` / `verification add` を Dispatcher と同時に追加
- [ ] human readable / `--json` 出力切替
- [x] RPCClient のエラー表示(rpcError / connectFailed 等を整形)

### 6.2 MCP サーバ

- [x] `hoy mcp` サブコマンドで stdio mode 起動
- [x] HoyProtocol のメソッドを MCP ツールとして公開(HoyTools.all)
- [x] daemon への JSON-RPC 中継(RPCClient.rawSend)
- [x] initialize / tools/list / tools/call の最小ハンドリング

---

## Phase 7: 運用最低限

- [ ] 監査ログの append 書き出し(ADR 0027、クエリ機能は MVP 外)
- [ ] reconciliation コマンド(ADR 0035、Git と SQLite の乖離検知・修復)
- [ ] バックアップ・リストア(SQLite ファイル + Git リポジトリ)
- [ ] エラー・パニック時のリカバリ動作

---

## Phase 8: dogfooding

- [ ] 自分(hiragram)が hoy の開発自体を hoy で管理する状態を作る
- [ ] 既存 ADR を Intent としてインポートする手順整備
- [ ] 摩擦をフィードバックして MVP の磨き込み

---

## 見送り(MVP外)

ADR 0031 で MVP 外と確定済み:

- Web UI / TUI
- ドリフト検出メタデータ(ADR 0021)
- 監査ログのクエリ機構
- 高度な権限・capability(ADR 0026)
- マルチ開発者対応(ADR 0029)
- 外部ツール統合(ADR 0032)
- 意味レベル差分(concept §6.3)
