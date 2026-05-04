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

- Stage 1: test-required。test が無い / 通らない task は complete できない
- **Stage 2 (実装済): test-first**。`testFirst: true` を付けた check は、
  pass の前に fail を観察した履歴 (`redObserved`) がないと gate を
  満たさない。`policy.json` の各 default verification に
  `"test_first": true` を、または `hoy policy add-default-verification
  --test-first` で指定する
- Stage 3 (将来): code と test を別 commit に強制(red commit と
  green commit の分離)

### Stage 2 の挙動詳細

- `markFailed` のときに `redObserved = true` がセットされる
- `markPassed` は `redObserved` を保持して遷移する
- 同一 task 内で再 run するとき、`VerificationRunner` は failed 状態の
  check を `prepareForRerun()` 経由で pending に戻す(`redObserved` を
  保持)。これにより `fail → impl 追加 → 再 run → pass` で
  `redObserved=true AND status=passed` の状態が成立し、gate を満たす
- ADR 0017 の統合後再走 (`resetToPending`) は **世界線リセット** なので
  `redObserved` を false に戻す。main が動いた後は再度「先 fail → 後 pass」
  を要求する
