# 0023. closed Intentのreopenは不可

- **Status**: Accepted
- **Related**: open-questions #3

## Context

closed Intent を再び active に戻す(reopen)を許すかを決める必要があった。

## Decision

closed Intent の **reopen は不可**。再着手したい場合は新しい Intent を作成する。前 Intent を `related` 等で参照できるようにする。

## Rationale

- 「closed」を歴史的事実として残すことで意思決定の追跡が clean になる
- reopen を許すと「これは同じ Intent か別 Intent か」という判断が運用上常につきまとう
- regression や再発に対しては、新 Intent + 旧 Intent への参照で十分追跡可能
- ADR 0008 で「内容修正は version 更新で扱う」と決めたため、close 前の修正は active のまま update すればよい

## Consequences

- closed Intent には書き込み不可(close操作以外)
- 「以前のIntentを参考にしたい」用途には新 Intent から旧 Intent を参照するメタデータが必要(`related_intents` のようなフィールド、別途設計)
- 誤って close した場合の救済は「新 Intent を作って同じ内容を書く」運用になる
