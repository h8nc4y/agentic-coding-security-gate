# HANDOFF

最終更新: 2026/07/28（Codex）
役割: 現況と次の一手だけを持つ project brain。完了履歴は `CHANGELOG.md`・git log・マージ済み PR を正とし、ここには残さない。要件は `docs/REQUIREMENTS.md`、タスクは `TASKS_BACKLOG.md`、運用契約は `AGENTS.md` が正本。

## 現在の状態

- T-024 では一般的な private-key container である `.key` を既存
  `private-key-block` rule の走査対象へ追加した。大小混在拡張子、
  redaction、値非再掲を合成回帰で固定し、新しい検出 rule・実 private 値・
  要件変更は追加していない。
- `main` は T-023 PEM text coverage まで統合済み（PR #41、merge commit `1543f48`）。直前の T-022 で Git index / worktree / child-process / path / deadline / output 境界を bounded かつ fail-closed に強化し、T-023 はその scanner の text-container 選択だけを補完した。
- T-023 では標準的な `.pem` text container を既存 `private-key-block` rule の走査対象へ追加した。大小混在拡張子、redaction、既存 binary skip を合成回帰で固定し、新しい検出 rule や実 private 値は追加していない。
- T-001〜T-024、Pester 0-tests false green（PR #37）、secret-assignment の prefix/placeholder 非対称、dotenv filename coverage を完了。既存の検出 rule 名・literal / placeholder 判定は変更していない。
- Git tag / GitHub Release は未作成（初回 release はゲート①で owner 承認待ち、資料は `docs/release-readiness-brief.md` / `docs/release-notes-draft.md`）。
- 要件正本は `docs/REQUIREMENTS.md`。現行の未決事項は同書 §10 Q1-Q9 と `TASKS_BACKLOG.md` の外部レビュー指摘。

## open PR

最新の open PR / open issue は GitHub を正とし、各着手時に再確認する。

## 最終検証結果（2026/07/28、T-024 KEY text coverage）

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| Windows / PowerShell 7 | `pwsh -NoProfile -ExecutionPolicy Bypass -File ./tests/scan-private-markers.Tests.ps1` | pass（53 cases + boundary self-test、196.9秒、exit 0） |
| Windows / PowerShell 5.1 | 同じ統合 test entrypoint（`powershell.exe` を強制） | fix後 pass（53 cases + boundary self-test、exit 0）。公式 support は PowerShell 7+ のまま |
| marker scan | scanner default `auto` mode（Git repoでは tracked index + worktree） | pass（41 files、29.7秒、exit 0） |
| whitespace / encoding / hidden Unicode | `git diff --check`、変更6ファイルの strict UTF-8 / NUL / CRLF / form-feed、`CONTRIBUTING.md` 記載pattern | pass。scanner本体の既存UTF-8 BOMを保持し、test fileはBOMなし + ASCII commentを維持 |
| independent review | frozen tree の correctness / regression review | pass（P0=0 / P1=0 / P2=0 / P3=0、commit clearance） |
| Gitleaks / Semgrep | local security scan | Gitleaks v8.30.1 は履歴28 commits・working treeとも pass。Semgrepは実装・docs 5 files / 47 rulesで0 findings |
| lint / 型 / build | 該当設定なし | 未確認 |

## 次の一手（優先順）

1. T-024 の frozen treeをcommit / pushし、PR / CI / merge / branch cleanupを完了する。
2. 外部レビュー台帳の scanner 実 private 値に関する指摘は owner 裁定待ち。裁定なしに要件・fixture 方針を変えない。
3. GitHub の open issue と backlog を再確認し、要件変更なしで閉じられる新しい coverage gap があれば次の自走タスクにする。
4. owner が `docs/REQUIREMENTS.md` §10 の Q1-Q9 に回答する（release GO の Q2 を含む）。
5. release / tag / workflow 変更はゲート①。実行せず `examples/release-tag-gate-summary.md` の形式で停止する。

## 既知の問題・残懸念

- scanner の detector は best-effort。全 secret 形式の完全検出は保証せず、公開前の最終判断は Gitleaks / Semgrep 等の併用と人間レビューを前提とする（検出範囲の詳細はテストが正本）。一方、Git / path / process / deadline / report の曖昧な境界は exit 2 で fail closed にする。
- 公式 support は `pwsh` 7+。Windows PowerShell 5.1 の実測 pass は境界回帰の補助証跡であり、support 契約の変更ではない。
- UTF-8 BOMなしの test fileへ日本語commentを追加すると、Windows PowerShell 5.1 がCP932として誤解釈し、直後の代入をcomment化した。追加commentを既存styleのASCIIへ戻して53 cases passを再確認した。scanner本体は既存のUTF-8 BOMを保持する。
- `.key` がbinary DER等でstrict UTF-8 decode不能な場合は、既存のintegrity経路でexit 2へfail closedする。binary内容自体の識別はbest-effort scannerの射程外。
- sandbox 環境からの GitHub 認証確認は false negative があり得る。keyring-capable 経路で再確認してから認証問題と判断する。
- SKILL.md / examples への変更は `CONTRIBUTING.md` の攻撃面レビュー観点（逐行レビュー・hidden-unicode 検査）を必ず通す。
