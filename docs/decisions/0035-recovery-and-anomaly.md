# 0035. 復旧手段と暴走検知の方針

- **Status**: Accepted
- **Related**: open-questions #8

## Context

ADR 0011 / 0017 / 0023 / 0034 で個別の失敗モード(agent停止、統合衝突、壊れた変更、誤close)は対処済み。残る論点:

- (A) daemon 自体が壊れた場合の復旧
- (B) 暴走agent の検知
- (C) 一括取消(mass-revert)

## Decision

### (A) 復旧手段

以下を MVP で提供する:

- **reconciliation コマンド**: daemon 内部状態と Git 実態の乖離を検出・修復(ADR 0034 で言及済み)
- **バックアップ・リストア**: daemon の状態ディレクトリを export / import するコマンド
- **状態整合性チェック**: 起動時に内部不整合(孤立Task、claim矛盾など)を検出して報告

### (B) 暴走検知

daemon は **検知も自動制止も行わない**。代わりに統計メタデータを公開する:

- Principal ごとの単位時間あたり Task 完了数
- claim 取得・release 頻度
- 直近の操作履歴

閾値判定・通知・自動制止は外部 hook(or 外部監視ツール)の責務。ADR 0021(ドリフト検出)と同じ思想。

### (C) 一括取消(mass-revert)

MVPではデータモデル上の一括 revert は持たない。Task 単位 revert(ADR 0034)の連続として実行する。CLI の利便機能として「条件にマッチする Task を順次 revert」のような束ねコマンドは提供してよいが、内部的には個別 revert の繰り返し。

## Rationale

- 復旧手段は MVP 必須(daemon が壊れたら全データを失うのは許容できない)
- 暴走検知を daemon 内に持つと「閾値はいくつか」という運用判断が daemon の責務になり、ADR 0002 の方針と矛盾しやすい
- 一括 revert を一級操作にすると意味論が複雑化(部分失敗時の挙動、依存関係の扱い等)。Task単位の連続で十分

## Consequences

- daemon の起動シーケンスに整合性チェックが入る
- バックアップは「状態ディレクトリ + Git 内部リポジトリ」のセット
- 暴走検知hook を書きたいプロジェクトは統計APIを叩く
- 大量 revert は遅い可能性があるが、データモデル整合性を優先
- reconciliation の意味論(乖離があった時にどちらを正とするか、Git or daemon)は実装段階で詳細化が必要
