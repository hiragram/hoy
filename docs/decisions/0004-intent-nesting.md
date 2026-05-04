# 0004. Intentは入れ子可、Taskは入れ子不可

- **Status**: Accepted
- **Related**: open-questions #1

## Context

「ユーザー認証を改善する」のような大きな粒度と「ログイン画面のパスワード欄に表示切替ボタンを足す」のような小さい粒度が、両方 Intent として表現されうる。これらをどう構造化するか。

## Decision

- **Intent は入れ子可能**(親 Intent → 子 Intent の木構造を許す)
- **Task は入れ子不可**(フラット)

## Rationale

- 大小の粒度が混在する Intent を一様に扱うには木構造が自然
- Task を入れ子可にすると「サブタスク分割」問題がぶり返す。Task の中で検証経路を複数持てる(concept.md §3)ことで分割不要にする方針と整合
- Task は実装の自然な単位として保ち、構造化したい場合は Intent 側で表現する

## Consequences

- Intent 間に親子関係を持つフィールドが必要
- Task は単一階層のため検索・集計がシンプル
- 「Intent のサブツリー全体に紐づく Task 一覧」のようなクエリは Intent 木の走査で表現できる
