# HANDOFF

最終更新: 2026/07/30（Codex）
役割: 現況と次の一手だけを持つ project brain。完了履歴は `CHANGELOG.md`・git log・マージ済み PR を正とし、ここには残さない。要件は `docs/REQUIREMENTS.md`、タスクは `TASKS_BACKLOG.md`、運用契約は `AGENTS.md` が正本。

## 現在の状態

- T-029 では Terraform の `.tf` / `.tfvars` が text-file routing から漏れる
  非対称を、case-insensitive な allowlistから既存 ruleへ到達させて解消した。
  redaction、代入文と値の非再掲を synthetic regression で固定する変更を
  統合し、新しいrule・redaction・integrity semanticsは変更していない。
- T-028 では CI の trigger・job・runner・実行 command・権限を変えず、
  `actions/checkout` を公式 v4.4.0 tag の immutable SHA へ固定した。
  checkout credential は保持せず、quality gate に25分の上限を設定した。
- T-027 では `.vue` / `.svelte` / `.astro` がtext-file routingから漏れる
  非対称を解消した。case-insensitiveなallowlistから既存detectorへ到達させ、
  新しいrule・redaction・integrity semanticsは変更せず、大小混在拡張子と
  値非再掲をsynthetic regressionで固定した。
- T-026 では `.mjs` / `.cjs` / `.mts` / `.cts` がtext-file routingから
  漏れる非対称を解消した。case-insensitiveなallowlistから既存JS / TS
  detectorへ到達させ、新しいrule・redaction・integrity semanticsは
  変更せず、大小混在拡張子と値非再掲をsynthetic regressionで固定した。
- T-025 では `.js` / `.ts` と同系の `.jsx` / `.tsx` が text-file routing
  から漏れる非対称を、既存 detector・redaction・integrity semantics を
  変えずに解消した。大小混在拡張子、既存 rule への到達、redaction、
  assignment 全体と値単体の非再掲を合成回帰で固定した。
- T-024 では一般的な private-key container である `.key` を既存
  `private-key-block` rule の走査対象へ追加した。大小混在拡張子、
  redaction、値非再掲を合成回帰で固定し、新しい検出 rule・実 private 値・
  要件変更は追加していない。
- `origin/main` は T-029 Terraform text coverage まで統合済み。
  T-025〜T-027とT-029は各source形式を既存ruleへ到達させ、
  T-028はscanner・secret-assignment・public form・Pester契約を変更していない。
- T-023 では標準的な `.pem` text container を既存 `private-key-block` rule の走査対象へ追加した。大小混在拡張子、redaction、既存 binary skip を合成回帰で固定し、新しい検出 rule や実 private 値は追加していない。
- T-001〜T-029、Pester 0-tests false green（PR #37）、secret-assignment の prefix/placeholder 非対称、dotenv filename coverage を現行treeで完了。T-029 は検出 rule 名・literal / placeholder 判定を変更していない。
- Git tag / GitHub Release は未作成（初回 release はゲート①で owner 承認待ち、資料は `docs/release-readiness-brief.md` / `docs/release-notes-draft.md`）。
- 要件正本は `docs/REQUIREMENTS.md`。現行の未決事項は同書 §10 Q1-Q9 と `TASKS_BACKLOG.md` の外部レビュー指摘。

## open PR

2026/07/30 時点で open PR / open issue は0件。最新状態はGitHubを正とし、
各着手時に再確認する。

## 最終検証結果（2026/07/30、T-029 Terraform text coverage）

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| TDD RED | base + Terraform extensionのsynthetic regressionだけ | 既存56 casesはpassし、新規caseだけが `Expected '1' but got '0'` でfail。boundary self-testはpass、stderr 0 |
| PowerShell 7 | scanner regression / repository marker scan | 実装treeとexact merge treeで57 cases + boundary self-test pass。実装treeはtracked 42 files、clean merge treeはtracked 35 files pass。すべてexit 0。test wrapper stderrはCLIXML information/progressのみでErrorRecord / FAIL / Exceptionは0 |
| whitespace / encoding | `git diff --check`、変更7ファイルのstrict UTF-8 / BOM / NUL / CRLF / trailing whitespace / form-feed | pass。scanner本体の既存UTF-8 BOMを保持し、test fileはBOMなし + ASCII commentを維持 |
| Gitleaks | worktree / history scan（61 non-merge commits） | ともにleak 0 |
| Semgrep | `p/default`で変更7パス / base同一7パス | 両方exit 0、error 0。既存synthetic JWT fixtureの同一1件だけでdelta 0 |
| independent review | correctness / regression / public-safety review | P0=0 / P1=0 / P2=0 / P3=0でCLEAR |
| global hook | staged Gitleaks / Semgrep | Gitleaks pass、Semgrepは対象fileなしでskip |
| GitHub CI | PR #53 / `origin/main` push | runs `30534185902` / `30534425553` ともにsuccess |
| integration | reviewed tree / merge tree、ancestor、cleanup | tree一致、feature commitは`origin/main`のancestor。task / post-main worktreeとlocal / remote branchを削除済み |

## 次の一手（優先順）

1. 外部レビュー台帳の scanner 実 private 値に関する指摘は owner 裁定待ち。裁定なしに要件・fixture 方針を変えない。
2. GitHub の open issue と backlog を再確認し、要件変更なしで閉じられる新しい coverage gap があれば次の自走タスクにする。
3. owner が `docs/REQUIREMENTS.md` §10 の Q1-Q9 に回答する（release GO の Q2 を含む）。
4. release / tag / workflow 変更はゲート①。実行せず `examples/release-tag-gate-summary.md` の形式で停止する。

## 既知の問題・残懸念

- scanner の detector は best-effort。全 secret 形式の完全検出は保証せず、公開前の最終判断は Gitleaks / Semgrep 等の併用と人間レビューを前提とする（検出範囲の詳細はテストが正本）。一方、Git / path / process / deadline / report の曖昧な境界は exit 2 で fail closed にする。
- 公式 support は `pwsh` 7+。Windows PowerShell 5.1 の実測 pass は境界回帰の補助証跡であり、support 契約の変更ではない。
- UTF-8 BOMなしの test fileへ日本語commentを追加すると、Windows PowerShell 5.1 がCP932として誤解釈し、直後の代入をcomment化した。追加commentを既存styleのASCIIへ戻して53 cases passを再確認した。scanner本体は既存のUTF-8 BOMを保持する。
- `.key` がbinary DER等でstrict UTF-8 decode不能な場合は、既存のintegrity経路でexit 2へfail closedする。binary内容自体の識別はbest-effort scannerの射程外。
- sandbox 環境からの GitHub 認証確認は false negative があり得る。keyring-capable 経路で再確認してから認証問題と判断する。
- SKILL.md / examples への変更は `CONTRIBUTING.md` の攻撃面レビュー観点（逐行レビュー・hidden-unicode 検査）を必ず通す。
- CI の `actions/checkout` は公式 v4.4.0 tag のimmutable SHAへ固定し、
  credential非保持と25分timeoutを明示した。workflow変更はT-028の
  明示指示範囲だけに限定した。
