# 0048. workspace policy で default verifications を強制する

- **Status**: Accepted
- **Related**: ADR 0017, ADR 0047

## Context

hoy で開発する以上、TDD(テストありき)の規律を構造的に促したい。
ユーザの discipline 任せでは agent によってばらつくので、ワークスペース
側で「何を verify するか」を宣言できると都合がよい。

具体的なシーン:
- ある repo では「`swift test` が通ること」を全 task に課したい
- 別の repo では「lint も + smoke test も」を全 task に課したい
- ドキュメントタスクなど一部だけ免除したい

## Decision

`<root>/policy.json` を導入する:

```json
{
  "default_verifications": [
    {
      "kind": "automated",
      "category": "test",
      "spec": "swift test",
      "required": true
    }
  ]
}
```

- `Workspace.open` で読み込み、`workspace.policy` として公開
- 無ければ空 policy(従来挙動と完全互換)
- `task.create` 時に daemon が `policy.defaultVerifications` を新 task に
  自動 attach
- `task.create --skip-default-verifications` で個別 opt-out
- CLI: `hoy policy show` / `hoy policy add-default-verification` /
  `hoy policy clear`

## Rationale

- TDD を「process gate」として強制する最小単位は「task に test check が
  必須で attach されている」状態。これがあれば test を通さないと
  `task.complete --commit` が `verificationsNotSatisfied` で弾かれる
- 「test を **先に** 書くこと」までは強制しない(red→green の履歴を
  検証する状態機械はコストが高い、ADR 化を見送って discipline + ADR で
  教える)
- repo ごと(workspace ごと)に違うルールを許容するため、daemon 起動
  オプションでなく `policy.json` ファイルにする。git 管理可能、
  agent も読めば policy を理解できる
- 個別 opt-out が無いと「議論だけの task」「ドキュメント task」が詰まる。
  --skip-default-verifications でエスケープを残す

## Consequences

- repo に `policy.json` を置けば全 agent / 人間に同じ verification 規律が
  適用される
- 既存 workspace に影響なし(policy.json が無ければ default verifications
  は空)
- daemon は起動時に policy を 1 度読む。実行中の編集は反映されない
  (`Workspace.reloadPolicy()` を呼ぶ API は将来追加検討)
- ADR 0017 の検証経路再走と組み合わせ: main が動くと他 task の automated
  check が pending に戻り、再走を促す。policy で attach された test も
  対象なので、変更後に再 verify が要請される

## TDD 強制の段階

- Stage 1: ADR 0048 = test-required (本 ADR)。test が無い / 通らない
  task は complete できない
- Stage 2 (将来): test-first。最初の `verification.run` で fail を
  観察してから pass を観察した履歴がある task しか complete を許さない
- Stage 3 (将来): code → test の同一 commit を強制(red commit と
  green commit を分離)

Stage 1 を MVP の到達点として、それ以上は dogfooding で必要性が見えたら
別 ADR で。
