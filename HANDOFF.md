# HANDOFF

最終更新: 2026/07/25（Codex）
役割: 現況と次の一手だけを持つ project brain。完了履歴は `CHANGELOG.md`・git log・マージ済み PR を正とし、ここには残さない。要件は `docs/REQUIREMENTS.md`、タスクは `TASKS_BACKLOG.md`、運用契約は `AGENTS.md` が正本。

## 現在の状態

- `main` は dotenv filename の text scan coverage 修正まで統合済み。T-022 の変更セットでは、Git index / worktree / child-process / path / deadline / output 境界を bounded かつ fail-closed に強化した。scan-wide deadline は setup / launch / POSIX readiness / execution / drain / cleanup を単一の absolute budget で制限する。子 process は空の環境 map へ OS 由来・隔離済みの値だけを足し、POSIX は external/native `setsid` とも readiness 済みの live anchor を保持する。worktree は no-follow handle の file identity・change version・hash を最終 report 直前まで再検証し、cleanup は既知 artifact の bounded manifest だけを削除する。
- T-001〜T-022、Pester 0-tests false green（PR #37）、secret-assignment の prefix/placeholder 非対称、dotenv filename coverage を完了。既存の検出 rule 名・literal / placeholder 判定は変更していない。
- Git tag / GitHub Release は未作成（初回 release はゲート①で owner 承認待ち、資料は `docs/release-readiness-brief.md` / `docs/release-notes-draft.md`）。
- 要件正本は `docs/REQUIREMENTS.md`。現行の未決事項は同書 §10 Q1-Q9 と `TASKS_BACKLOG.md` の外部レビュー指摘。

## open PR

最新の open PR / open issue は GitHub を正とし、各着手時に再確認する。

## 最終検証結果（2026/07/25、T-022 scanner boundary hardening）

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| Windows / PowerShell 7 | `pwsh -NoProfile -ExecutionPolicy Bypass -File ./tests/scan-private-markers.Tests.ps1` | pass（51 cases + boundary self-test、207.6秒） |
| Windows / PowerShell 5.1 | 同じ統合 test entrypoint（`powershell.exe` を強制） | pass（51 cases + boundary self-test、192.7秒）。公式 support は PowerShell 7+ のまま |
| final boundary self-test | PS7 / PS5.1 / Ubuntu 24.04 PowerShell 7.5（Linux は read-only bind、`--network none`） | 全て pass（71.5秒 / 49.4秒 / 123.5秒）。external/native `setsid`、readiness、descendant cleanup、stale owner、nested cleanup reparse 拒否を含む |
| Linux full | 同じ container 条件で統合 test entrypoint | pass（51 cases + boundary self-test、237.4秒） |
| Windows / Linux marker scan | scanner `-ScanMode tracked`（Linux は同じ container 条件） | 両方 pass（43 files。Windows 33.2秒、Linux 44.6秒） |
| whitespace / hidden Unicode | `git diff --check HEAD --` と `CONTRIBUTING.md` 記載の pwsh チェック | pass |
| independent review | staged tree の security / correctness review | P1/P2/P3 remediation 済み。最終 frozen tree review 待ち |
| Gitleaks / Semgrep | local security scan | Gitleaks は履歴・working tree とも pass。Semgrep は変更実装3本で0 findings。全repoでは既存 mutable Actions tag 1件を検出 |
| lint / 型 / build | 該当設定なし | 未確認 |

## 次の一手（優先順）

1. 外部レビュー台帳の scanner 実 private 値に関する指摘は owner 裁定待ち。裁定なしに要件・fixture 方針を変えない。
2. GitHub の open issue と backlog を再確認し、要件変更なしで閉じられる新しい coverage gap があれば次の自走タスクにする。
3. owner が `docs/REQUIREMENTS.md` §10 の Q1-Q9 に回答する（release GO の Q2 を含む）。
4. release / tag / workflow 変更はゲート①。実行せず `examples/release-tag-gate-summary.md` の形式で停止する。

## 既知の問題・残懸念

- scanner の detector は best-effort。全 secret 形式の完全検出は保証せず、公開前の最終判断は Gitleaks / Semgrep 等の併用と人間レビューを前提とする（検出範囲の詳細はテストが正本）。一方、Git / path / process / deadline / report の曖昧な境界は exit 2 で fail closed にする。
- 公式 support は `pwsh` 7+。Windows PowerShell 5.1 の実測 pass は境界回帰の補助証跡であり、support 契約の変更ではない。
- Semgrep `p/default` の全repo scan は未変更の `.github/workflows/ci.yml` にある mutable `actions/checkout@v4` を1件検出する。今回変更した実装3本は0 findings。既存の synthetic JWT regression fixture も当該test fileを明示scanすると検出対象になるため、いずれも今回の scanner boundary remediation とは分離して扱う。
- sandbox 環境からの GitHub 認証確認は false negative があり得る。keyring-capable 経路で再確認してから認証問題と判断する。
- SKILL.md / examples への変更は `CONTRIBUTING.md` の攻撃面レビュー観点（逐行レビュー・hidden-unicode 検査）を必ず通す。
