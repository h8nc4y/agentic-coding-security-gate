# HANDOFF

最終更新: 2026/07/12（Claude Fable 5 → Codex 引き継ぎ）
役割: 現況と次の一手だけを持つ project brain。完了履歴は `CHANGELOG.md`・git log・マージ済み PR を正とし、ここには残さない。要件は `docs/REQUIREMENTS.md`、タスクは `TASKS_BACKLOG.md`、運用契約は `AGENTS.md` が正本。

## 現在の状態

- `main` は PR #27 まで統合済み。Git tag / GitHub Release は未作成（初回 release はゲート①で owner 承認待ち、資料は `docs/release-readiness-brief.md` / `docs/release-notes-draft.md`）。
- T-001〜T-017 完了。T-019（decision matrix）・T-020（CONTRIBUTING 攻撃面レビュー観点）は実装済みで PR マージ待ち。T-018（CODE_OF_CONDUCT / Issue・PR テンプレート）は未着手。
- 2026-07-12 に文書体系を整理: `docs/REQUIREMENTS.md` を要件正本として新設し、要件レビュー 2026-07 と validation 採否判断を統合（吸収元 2 ファイルと解決済み履歴 docs 2 ファイルは削除。git 履歴で参照可能）。

## open PR とマージ順

スタック構成。CI 緑と敵対的セルフレビュー（AGENTS §11）を確認し、上から順に `--delete-branch` 付きでマージする:

1. PR #29 `docs/adversarial-decision-matrix`（base: main）— T-019
2. PR #30 `docs/skill-attack-surface-review`（base: #29）— T-020
3. PR #31 `docs/handoff-codex-sync`（base: #30）— 2026-07-11 状態同期
4. PR #32 `docs/consolidate-project-docs`（base: #31）— 本文書整理

- PR #28 `docs/post-fable5-handoff`（base: main、2026-07-06 作成）は、追加しようとした引き継ぎ文書の役割が本整理で `HANDOFF.md` / `docs/REQUIREMENTS.md` に統合されたため **close 推奨**（マージ不要。close 時は supersede 理由をコメントに残す）。

## 最終検証結果（2026/07/12、docs/consolidate-project-docs ブランチ）

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| scanner tests | `pwsh -NoProfile -File ./tests/scan-private-markers.Tests.ps1` | pass（48 tests） |
| marker scan | `pwsh -NoProfile -File ./scripts/scan-private-markers.ps1` | pass（tracked mode） |
| hidden-unicode check | `CONTRIBUTING.md` 記載の pwsh チェック | pass（全 `.md` クリーン） |
| lint / 型 / build | 該当設定なし | 未実施扱い |

## 次の一手（優先順）

1. open PR を #29 → #30 → #31 → #32 の順にマージし、PR #28 を close する。
2. T-018 に着手する（`TASKS_BACKLOG.md` 参照。初回追加のため owner へ一言確認する趣旨を PR 本文に明記して進めてよい）。
3. owner が `docs/REQUIREMENTS.md` §10 の Q1-Q9 に回答する（release GO の Q2 を含む）。回答待ちの間の自走候補は `TASKS_BACKLOG.md` の新規候補から選ぶ。
4. release / tag / workflow 変更はゲート①。実行せず `examples/release-tag-gate-summary.md` の形式で停止する。

## 既知の問題・残懸念

- scanner は best-effort。全 secret 形式の完全検出は保証せず、公開前の最終判断は Gitleaks / Semgrep 等の併用と人間レビューを前提とする（検出範囲の詳細はテストが正本）。
- 検証ランタイムは `pwsh` 7+。Windows PowerShell 5.1 は互換対象外。
- sandbox 環境からの GitHub 認証確認は false negative があり得る。keyring-capable 経路で再確認してから認証問題と判断する。
- SKILL.md / examples への変更は `CONTRIBUTING.md` の攻撃面レビュー観点（逐行レビュー・hidden-unicode 検査）を必ず通す。
