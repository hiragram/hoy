# hoy

エージェント時代の開発プラットフォーム。GitHub的なワークフローをエージェントファーストで再設計するプロジェクト。

## ドキュメント

設計議論を進める前に、以下を必ず読むこと。

- @docs/concept.md — プロジェクト全体のコンセプトと設計思想
- @docs/decisions/README.md — 設計判断の索引(ADR)
- @docs/open-questions.md — まだ詰まっていない論点

## 進め方

- 設計判断は必ずADRとして `docs/decisions/NNNN-short-title.md` に記録する
- ADR を追加したら `docs/decisions/README.md` の索引も更新する
- 未決事項は `docs/open-questions.md` に残す
- 既存のADRに矛盾する変更を入れる場合は、対象ADRを `Superseded by NNNN` にして新しいADRを起票する

## 言語

ドキュメント・コミットメッセージ・議論はすべて日本語。
