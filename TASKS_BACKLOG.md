# Tasks Backlog

最終更新: 2026/07/12
運用: 本ファイルはタスク状態の正本。完了タスクの詳細・経緯は `CHANGELOG.md`・git log・マージ済み PR を参照する（ここには履歴注記を蓄積しない）。要件と拡充方針は `docs/REQUIREMENTS.md` が正本。

## タスク

| ID | タスク名 | 出典 | 優先度 | 状態 |
| --- | --- | --- | --- | --- |
| T-001〜T-017 | scanner 整備・boundary examples・release 準備資料・token/credential coverage 一式 | `CHANGELOG.md` / git log | — | done |
| T-018 | `CODE_OF_CONDUCT.md` と Issue / PR テンプレートを追加する | `docs/REQUIREMENTS.md` 旧レビュー §6 | 中 | todo（初回追加のため owner へ一言確認する趣旨を PR 本文に明記して進めてよい） |
| T-019 | adversarial decision matrix（合成シナリオ × 期待判断の静的表） | `docs/REQUIREMENTS.md` §5 | 中 | done（PR #29、マージ待ち） |
| T-020 | CONTRIBUTING へ skill 攻撃面レビュー観点を明文化 | `docs/REQUIREMENTS.md` §8 | 中 | done（PR #30、#29 の後にマージ） |

## 新規候補（着手前に `docs/REQUIREMENTS.md` §5・§10 と突き合わせる）

- open PR の処置: #29 → #30 → #31 → #32 の順にマージ、#28 は close（詳細は `HANDOFF.md`）。
- scanner の文脈付きルール拡充: Google OAuth client secret の credential file 文脈検出、owner 実利用に応じて Cloudflare / Vercel / Netlify 系。prefix 単独追加は限界効用逓減のため owner の Q4 回答を待つ。
- `examples/` 拡充: 新しい境界シナリオに限定し、合成データのみで追加。追加時は `docs/adversarial-decision-matrix.md` に対応行を検討する。
- 初回 release: owner の Q2 承認後にゲート①として実施（資料は `docs/release-readiness-brief.md`）。承認前は着手しない。
