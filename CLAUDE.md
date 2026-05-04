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

## 開発ルール

### テストフレームワーク

**Swift Testing** を使う(ADR 0042)。`import Testing` / `@Test` / `#expect` の作法。XCTest は使わない。

### TDD: t-wada スタイルを厳密に

t-wada(和田卓人)氏が提唱するTDDのサイクルを厳密に守る:

1. **Red**: まず失敗するテストを書く。テストが失敗することを必ず確認する(コンパイルエラーも「失敗」のうち)
2. **Green**: テストを通す**最小限**のコードを書く。仮実装(ベタ書きの定数返却など)から始めて、三角測量で一般化する
3. **Refactor**: テストが通ったままリファクタリング。重複の除去・命名改善のみ。新しい振る舞いは追加しない

ルール:

- **テストなしで実装を進めない**。まずテストを書く
- **一度に1つのテストだけ**を Red にする。複数のテストを同時に失敗させない
- **TODOリスト**を活用する。実装前に「このコンポーネントに必要なテストケース」を箇条書きにし、上から1つずつ Red→Green→Refactor で潰していく
- **仮実装(Fake It)を恐れない**。最初のテストは「return 42」のようなベタ書きで通してよい。次のテストで一般化に追い込まれるのが正しい
- **明白な実装(Obvious Implementation)もOK**。実装が自明な場合は仮実装をスキップして直接書いてよい
- **テストを消すな**。Greenにするためにテストを書き換えるのは禁止。実装側を直す

### コミット

**Conventional Commits** に従う。

形式:

```
<type>(<scope>): <subject>

<body>

<footer>
```

主要な type:

- `feat`: 新機能
- `fix`: バグ修正
- `docs`: ドキュメントのみの変更
- `refactor`: 振る舞いを変えないリファクタリング
- `test`: テストの追加・修正
- `chore`: ビルド・ツール・補助変更
- `perf`: 性能改善

ルール:

- subject は命令形・小文字始まり・末尾ピリオドなし
- 1コミット1論理変更。RedコミットとGreenコミットを分けるかは状況判断(細かく分けるのが望ましい)
- ADR追加時は `docs(adr): ...` を使う
- breaking change は body 内で `BREAKING CHANGE:` を明記

## 言語

ドキュメント・コミットメッセージ・議論はすべて日本語。ただし Conventional Commits の type と Conventional な英語キーワード(`BREAKING CHANGE` 等)は英語のまま。
