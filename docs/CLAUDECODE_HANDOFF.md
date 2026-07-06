# ClaudeCode 司令塔 引き継ぎ — agentic-coding-security-gate (post-Fable5)

本書は **2026-07-08 以降、または Fable5 の利用上限到達後**に有効な引き継ぎ文書。
テンプレ正本は codex-global-context repo の `templates/agent-handoff-prompt.md`。
本 repo は public であるため、ローカル絶対パス・他 repo の内部情報・個人環境の詳細は書かない。

作成日時: 2026/07/06 JST

## 役割分担（モデル固定名を使わない）

- **司令塔**: Claude Opus 4.8 role。要件再定義・設計判断・レビュー・実装委譲文の作成を担当。
- **実装**: `mcp__codex__codex`（通常タスク）/ `mcp__codex-deep__codex`（難所のみ、xhigh）。
- **並列調査・機械的作業**: Sonnet 5 subagent（Agent tool 経由）。
- **フロントエンド/UI**: `frontend-developer` subagent。本 repo は現時点で UI 実装なし
  （PowerShell スキャナ・回帰テスト・Markdown skill/docs が中心）。

固定モデル名（Fable5 等）をゴールや運用ルールの恒常記述に使わず、役割名で書くこと。

## 調査範囲と注意（引き継ぎ時点の限界）

- 根拠は repo 内の `README.md` / `HANDOFF.md` / `TASKS_BACKLOG.md` / `docs/` の読み取りのみ。
- 外部API、GitHub Actions実行、CI実行結果、Cloudflare、その他クラウドの実挙動は未確認。
- secret・token・実データ・実ユーザー情報は読んでいない・書いていない。
- 既存資料は現状把握の材料であり、要件定義の最終正本ではない。市場・仕様調査は陳腐化を疑って
  再確認すること。

## リポジトリの概要

AI coding agent が Git / GitHub / browser / MCP / CLI / cloud / API などの境界を越える前に、
secret・private context・real data・paid operation の漏えいや誤実行を防ぐための Codex-style
skill を提供する OSS リポジトリ。公開配布向けの `SKILL.md`、合成例（`examples/`）、ローカル
private marker scan（`scripts/scan-private-markers.ps1`）、回帰テスト（`tests/`）、CI
（`.github/workflows/ci.yml`）を含む。

## 主要ファイル（reading order）

1. `AGENTS.md` — Codex 側運用ポリシー（Claude Code とルール共有元）
2. `HANDOFF.md` — 現況サマリ、完了タスク一覧、既知の問題、次アクション候補
3. `TASKS_BACKLOG.md` — タスク一覧（T-001〜、正本）
4. `docs/REQUIREMENTS_REVIEW_2026-07.md` — 要件再検討メモ。owner 質問 Q1-Q9、タスク候補 T-017〜T-020
5. `docs/VALIDATION_DECISION.md` — mandatory markdown lint / external skill validator を導入しない判断
6. `SKILL.md` — エージェントが読み込むスキル本体
7. `README.md` — repo 概要、install 手順、動作前提（`pwsh` 7+ が検証ランタイム）

## 現状サマリ（引き継ぎ時点）

- `main` は直近マージ済み PR まで反映済み。private marker scanner は複数の credential 形式
  （Anthropic/JWT、npm auth-token、PyPI、RubyGems、GitHub classic token 群、GitLab/Hugging
  Face/Slack webhook/SendGrid など）の合成 fixture 検出を持ち、回帰テストで RED → GREEN 確認済み。
- release readiness brief / release notes draft は docs-only で追加済み。Git tag / GitHub
  Release の作成は owner 承認待ちで未実行（ゲート）。
- lint / 型チェック / build は該当する設定ファイルが repo にないため未実施扱い。テストは
  `pwsh -NoProfile -File .\tests\scan-private-markers.Tests.ps1` で実行する。
- 詳細な完了タスク・commit 対応表・最終検証結果は `HANDOFF.md` を正本として参照する。本書では
  重複させない。

## 次アクション候補

1. owner が `docs/REQUIREMENTS_REVIEW_2026-07.md` の Q1-Q9 に回答するのを待つ（release GO
   判断を含む）。回答が揃うまで release/tag/GitHub Release の実行はしない。
2. owner 回答待ちの間の自走候補: CODE_OF_CONDUCT・Issue/PR テンプレート整備、adversarial
   decision matrix の作成、CONTRIBUTING への skill 攻撃面レビュー観点の明文化（`HANDOFF.md`
   「次にやるべき候補」参照）。
3. private marker scanner のカバレッジ拡充候補（新しい credential 形式、誤検出防止のネガティブ
   テスト）は `TASKS_BACKLOG.md` の残タスクを確認してから着手する。
4. 着手前に必ず `git status --short --branch` と GitHub の open PR / issue を確認し、他エージェント
   の進行中作業を壊さない。

## Stop only when（費用・外部リスクの境界）

有料API/有料クラウド/課金、OAuth/secret/token入力、実ユーザー/実データの外部送信、ストア提出・
公開release（tag push・GitHub Release作成を含む）・production deploy、または人間の意思決定なし
には進めない product 判断が必要なときだけ止まる。止まる場合は必要な操作・理由・代替案・確認
したい質問を明確にする。

## 委譲時の注意

Codex へ委譲する際は self-contained spec（対象ファイル・受け入れ条件・検証コマンド・書き込み
許可範囲）を渡し、`multi-agent-delegation` skill の規律（再委譲禁止文言・成果物の実在検証）に
従う。本 repo は public のため、委譲プロンプト・レビュー・PR 本文・issue 本文にローカル絶対
パス、他 repo の内部情報、secret、実データを含めない。scanner の合成 fixture はあくまで
synthetic であることを明記し、実際の secret 値を模した文字列を貼る場合も「合成例」であることを
本文中に明記する。

## 既存引き継ぎメモとの関係

本 repo には過去に `docs/CLAUDECODE_FABLE5_HANDOFF.md` / `docs/CLAUDECODE_FABLE5_PROMPT.md`
という repo-local な未コミットドラフトが存在した時期がある（Fable5 固定名の旧テンプレ運用時）。
これらは commit 履歴には残っていないため、本書からの直接リンクは張らない。同種の記録が今後
`docs/` に commit された場合は、本書の「役割分担」節を「Fable5」から「司令塔モデル」に読み替えた
延長として扱う。
