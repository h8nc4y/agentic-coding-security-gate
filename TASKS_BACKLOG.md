# Tasks Backlog

最終更新: 2026/07/22
運用: 本ファイルはタスク状態の正本。完了タスクの詳細・経緯は `CHANGELOG.md`・git log・マージ済み PR を参照する（ここには履歴注記を蓄積しない）。要件と拡充方針は `docs/REQUIREMENTS.md` が正本。

## タスク

| ID | タスク名 | 出典 | 優先度 | 状態 |
| --- | --- | --- | --- | --- |
| T-001〜T-017 | scanner 整備・boundary examples・release 準備資料・token/credential coverage 一式 | `CHANGELOG.md` / git log | — | done |
| T-018 | `CODE_OF_CONDUCT.md` と Issue / PR テンプレートを追加する | `docs/REQUIREMENTS.md` 旧レビュー §6 | 中 | done |
| T-019 | adversarial decision matrix（合成シナリオ × 期待判断の静的表） | `docs/REQUIREMENTS.md` §5 | 中 | done |
| T-020 | CONTRIBUTING へ skill 攻撃面レビュー観点を明文化 | `docs/REQUIREMENTS.md` §8 | 中 | done |

## 新規候補（着手前に `docs/REQUIREMENTS.md` §5・§10 と突き合わせる）

- scanner の文脈付きルール拡充: Google OAuth client secret の credential file 文脈検出、owner 実利用に応じて Cloudflare / Vercel / Netlify 系。prefix 単独追加は限界効用逓減のため owner の Q4 回答を待つ。
- text file coverage: `.env` / `.env.example` が拡張子 allowlist 外で scan されないことを合成 fixture で確認済み。filename 文脈で安全に対象化する。
- `examples/` 拡充: 新しい境界シナリオに限定し、合成データのみで追加。追加時は `docs/adversarial-decision-matrix.md` に対応行を検討する。
- 初回 release: owner の Q2 承認後にゲート①として実施（資料は `docs/release-readiness-brief.md`）。承認前は着手しない。

## 外部レビュー指摘の台帳（2026-07-15 maxエフォート横断レビュー）

読取専用レビュー（実行検証なし）の指摘。採否と実装は次担当が判断する。完了時は行頭を [x] にし、対応PRを追記する。

- [ ] scan-private-markers.ps1:75-77 — 実private値の分割literal埋め込み(019と同件) — 018方式の外部ロードへ。オーナー裁定待ち。
- [x] tests/scan-private-markers.Tests.ps1 — Pester 実行が 0 tests で false green になる問題を再現し、直接実行互換の 1-test adapter と正しい入口コマンドで解消（PR #37）。
- [x] secret-assignmentルール — 接頭辞付き key の literal 値を検出し、空値・明示的 runtime placeholder だけを allowlist する文脈判定で非対称を解消。
