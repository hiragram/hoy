# 0026. 初期権限モデルは識別+claim駆動、capability細粒度は将来拡張

- **Status**: Accepted
- **Related**: open-questions #4

## Context

daemon に接続する agent に対する権限制御の粒度を決める必要があった。

選択肢:
- (a) 認証なし・全権限
- (b) Principal 識別のみ、権限は一律
- (c) capability-based(操作別token)
- (d) role-based(`worker`/`reviewer`/`observer` 等)

## Decision

**(b) を初期実装、(c) は将来拡張余地として残す**:

- 接続には Principal 認証が必要(ADR 0025)
- 書き込み操作の制御は ADR 0009 / 0012 の **claim 機構**で行う(claim者でなければ Intent / Task に書き込めない)
- 細粒度な capability(「この Intent には read のみ」「この操作だけ許可」)は初期版では持たない

## Rationale

- ローカル daemon の現実的な脅威は「悪意あるagent」より「事故」(別 agent が誤って書き込み等)
- claim 機構で「同時に1人だけ書き込める」が既に保証されているため、追加の権限機構なしでも事故は防げる
- Principal 識別により監査ログ(誰が何をしたか)は正確に取れる
- capability/role は将来 token に scope を持たせる形で後付けできる
- 初期版の複雑さを最小化することで実装速度と運用容易性を優先

## Consequences

- 同じ daemon に接続できる agent は、claim を取れば同等の操作ができる
- 「読み取り専用agent」のような分離は将来拡張(token に scope を入れて実現)
- リモート連携や複数開発者(open-questions #5)が現実化した時点で本ADRの再検討が必要
- 監査ログは ADR 0006 の `created_by` と ADR 0025 の Principal 情報で構成される
