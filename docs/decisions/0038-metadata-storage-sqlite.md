# 0038. メタデータストレージはSQLite

- **Status**: Accepted
- **Related**: ADR 0013, ADR 0027

## Context

Intent / Task / claim / 検証経路 / 監査ログ などのメタデータの保管方式を決める必要があった。Git は変更セットの保管(ADR 0013)に使うが、メタデータは別のストアが要る。

選択肢:
- (a) SQLite
- (b) 自前のファイルベース(JSON / TOML、Git notes 利用)
- (c) 組み込み KVS(sled, LevelDB 等)

## Decision

メタデータストレージとして **SQLite** を採用する。

## Rationale

- ファイル一個で完結、ローカル daemon (ADR 0015) との相性が良い
- トランザクション・WAL・FK制約・インデックスなど成熟した機能が標準で揃う
- SQL でクエリできる(監査ログの projection、Intent/Task の検索など)
- Swift から `SQLite.swift` 等で扱える
- append-only な監査ログ(ADR 0027)もテーブル+トリガーで自然に表現できる
- (b) は車輪の再発明で時間を浪費する
- (c) はクエリ性能が SQL に比べて貧弱、観測性が下がる

## Consequences

- daemon の状態ディレクトリに `state.db` のような形で SQLite ファイルを置く
- スキーマのマイグレーション戦略が必要(別途検討)
- バックアップは SQLite ファイル + Git 内部リポジトリのセット(ADR 0035 と整合)
- 並行アクセスは SQLite の WAL モードで対応(daemon が単一プロセスなので競合は少ない)
- 将来的にリモート同期(ADR 0029 の将来拡張)が必要になった場合、SQLite ベースのレプリケーション戦略(litestream 等)が選択肢になる
