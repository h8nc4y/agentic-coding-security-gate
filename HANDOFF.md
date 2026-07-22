# HANDOFF

最終更新: 2026/07/22（Codex）
役割: 現況と次の一手だけを持つ project brain。完了履歴は `CHANGELOG.md`・git log・マージ済み PR を正とし、ここには残さない。要件は `docs/REQUIREMENTS.md`、タスクは `TASKS_BACKLOG.md`、運用契約は `AGENTS.md` が正本。

## 現在の状態

- `main` は T-018 の community health files 追加まで統合済み。Git tag / GitHub Release は未作成（初回 release はゲート①で owner 承認待ち、資料は `docs/release-readiness-brief.md` / `docs/release-notes-draft.md`）。
- T-001〜T-020 完了。T-018 として `CODE_OF_CONDUCT.md`、public-safe な Issue forms、PR template を追加し、private-first reporting を既存 `SECURITY.md` へ一本化した。
- 要件正本は `docs/REQUIREMENTS.md`。現行の未決事項は同書 §10 Q1-Q9 と `TASKS_BACKLOG.md` の外部レビュー指摘。

## open PR

2026-07-22 確認時点で open PR / open issue はなし。

## 最終検証結果（2026/07/22、T-018）

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| entry command | `Invoke-Pester tests/scan-private-markers.Tests.ps1 / scripts/scan-private-markers.ps1` | fail（`EnableExit` 引数変換。次タスクで整合修正） |
| scanner tests | `pwsh -NoProfile -ExecutionPolicy Bypass -File ./tests/scan-private-markers.Tests.ps1` | pass（exit 0） |
| marker scan | `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/scan-private-markers.ps1` | pass（tracked mode、33 files） |
| Issue forms | YAML parse・必須キー・ID 重複チェック | pass |
| hidden-unicode check | `CONTRIBUTING.md` 記載の pwsh チェック | pass（全 `.md` クリーン） |
| lint / 型 / build | 該当設定なし | 未確認 |

## 次の一手（優先順）

1. 外部レビュー台帳の scanner 実 private 値に関する指摘は owner 裁定待ち。裁定なしに要件・fixture 方針を変えない。
2. 次の自走可能タスクとして、`.Tests.ps1` と `Invoke-Pester` の不整合指摘を再現・評価し、命名変更か Pester 化を選ぶ。
3. owner が `docs/REQUIREMENTS.md` §10 の Q1-Q9 に回答する（release GO の Q2 を含む）。
4. release / tag / workflow 変更はゲート①。実行せず `examples/release-tag-gate-summary.md` の形式で停止する。

## 既知の問題・残懸念

- scanner は best-effort。全 secret 形式の完全検出は保証せず、公開前の最終判断は Gitleaks / Semgrep 等の併用と人間レビューを前提とする（検出範囲の詳細はテストが正本）。
- 検証ランタイムは `pwsh` 7+。Windows PowerShell 5.1 は互換対象外。
- sandbox 環境からの GitHub 認証確認は false negative があり得る。keyring-capable 経路で再確認してから認証問題と判断する。
- SKILL.md / examples への変更は `CONTRIBUTING.md` の攻撃面レビュー観点（逐行レビュー・hidden-unicode 検査）を必ず通す。
