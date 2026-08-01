# HANDOFF

最終更新: 2026/08/02（Codex）
役割: 現況と次の一手だけを持つ project brain。完了履歴は `CHANGELOG.md`・git log・マージ済み PR、要件は `docs/REQUIREMENTS.md`、タスクは `TASKS_BACKLOG.md`、運用契約は `AGENTS.md` が正本。

## 現在の状態

- T-037 では大小文字が混在する `.rules` policy file をtext-file routingへ追加し、既存detector・placeholder・redaction・integrity semanticsを変えずsilent skipを解消する。
- 5-file synthetic fixture は通常／1層 `.example` の大小文字positive 4件と多重suffix negative 1件を固定し、既存 `email-address` finding、redaction、policy recordと値の非再掲を検証する。policy専用 ruleや実データは追加していない。
- T-001〜T-037、Pester 0-tests false green（PR #37）、secret-assignment の prefix / placeholder 非対称、dotenv filename coverage は現行 tree で完了。
- observable な Git / GitHub / CI 状態は固定せず、各 work unit 着手時に再計測する。
- Git tag / GitHub Release は未作成。初回 release、workflow 変更、`docs/REQUIREMENTS.md` §10 Q1-Q9 は owner gate を維持する。

## 最終検証結果（2026/08/02、T-037 rules policy text coverage）

| 種別 | 結果 |
| --- | --- |
| TDD RED | 既存64 cases + boundary self-test は pass。追加 `.rules` case のみ exit 0 で期待 exit 1 に失敗 |
| PowerShell 7 | scanner regression 65 cases + boundary self-test pass |
| Windows PowerShell 5.1 | scanner regression 65 cases + boundary self-test pass（BOMなしtest fileの新規commentは既存規約どおりASCII。公式 support は `pwsh` 7+） |
| 独立レビュー | 初回P2 3件（compound境界、policy sentinel、停止条件同期）を修正。再review P2 1件（Q4再開条件の曖昧さ）を修正。最終reviewはP0〜P3 actionable findingなし |
| repository marker scan | 変更中treeは PowerShell 7 / Windows PowerShell 5.1 ともindex/worktree snapshot合計42 files、exit 0 |
| whitespace / encoding | `git diff --check` pass。変更7 files は strict UTF-8 / LF / NULなし。scanner本体だけ既存BOMを保持 |
| Gitleaks | working directory / Git history とも `--redact` で exit 0 |
| Semgrep | T-033時のdirect wrapperは実行policyにreject済み。同じ直接実行を再試行せず未確認を維持 |

## 次の一手（優先順）

1. 外部レビュー台帳の scanner 実 private 値指摘は owner 裁定待ち。裁定なしに要件・fixture 方針を変えない。
2. extension inventory 起点の拡充は T-037 で停止する。再現可能な false negative または明示的な正本driftは Q4 の判断材料として記録し、owner が Q4 で再開を認めるまで拡張子追加を再開しない。
3. owner が `docs/REQUIREMENTS.md` §10 Q1-Q9 に回答する。
4. release / tag / workflow 変更はゲート①。承認前は実行しない。

## 既知の問題・残懸念

- scanner は best-effort。専用 secret scanner と人間レビューを併用する。Git / path / process / deadline / report の曖昧な境界は exit 2 で fail closed にする。
- batch parser は `SET` の単一行 subset であり、`SETX`、`SET /A`、caret escape、複数行 continuation、substring / substitution を含む cmd 文法全体は扱わない。認識外の runtime 形は安全側へ allowlist せず finding になり得る。
- SQL bind placeholder（`:name` / `$1` / `?`）は既存 placeholder allowlist の対象外。secret-like keyへの代入では finding になり得るため、実際のfalse positive証拠なしにallowlistを拡張しない。
- legacy CP932 / UTF-16 batch が strict UTF-8 decode 不能なら既存 integrity 経路で exit 2 となる。
- GitHub-hosted runner は固定済み checkout action の Node.js 20 非推奨 warning を報告中。quality gate は pass しているが、workflow 更新は owner gate のため自動変更しない。
