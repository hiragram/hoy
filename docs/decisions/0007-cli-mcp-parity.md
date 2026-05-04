# 0007. CLIとMCPは同等、APIが一次

- **Status**: Accepted
- **Related**: open-questions #1

## Context

Task 起票を人間/エージェント両方に許容する以上、CLI と MCP の操作レンジが揃っていないとエコシステムが歪む。「CLI にあるけど MCP にない操作」が出ると、エージェントが CLI を shell 実行しはじめる。

## Decision

- プロトコル(API)を一次とする
- CLI と MCP はどちらも API の薄いラッパーとして実装する
- CLI でできる操作は MCP でもできる、逆も同様

## Rationale

- API を中核に置くことで、CLI/MCP 以外のクライアント(GUI、Web、エディタ統合など)も同じ土俵に乗る
- どちらかに片寄った機能差が、エージェント運用の歪みを生むのを防ぐ
- LSP がエディタを問わずに動くのと同じ構図

## Consequences

- 機能追加時は「API に追加 → CLI/MCP の双方に露出」というフローを守る必要がある
- ドキュメントも API リファレンスを正、CLI/MCP は派生という扱いにする
- 「人間専用の操作」「エージェント専用の操作」という非対称性を許す場合は、明示的に ADR で定める
