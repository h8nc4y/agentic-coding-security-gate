# Tasks Backlog

棚卸し日時: 2026/06/11 20:53:09 JST
最終更新: 2026/07/03 23:45 JST

## Sources

- 既存タスク管理ファイル: 該当なし (`TASKS_BACKLOG.md` / `TODO.md` / `TASKS.md` は未存在)
- README / docs: 明示的な未完了要件は該当なし
- AGENTS.md / `.codex`: リポジトリ内には該当なし
- TODO / FIXME: 該当なし (`rg -n "TODO|FIXME"` で一致なし)
- テスト / lint / 型チェック: `pwsh -NoProfile -File .\tests\scan-private-markers.Tests.ps1` は成功（36 tests）。`pwsh -NoProfile -File .\scripts\scan-private-markers.ps1` も成功（tracked mode / 29 files）。lint / 型チェック / build は該当する設定ファイルなし。
- git status: PR #26（T-017 scanner marker batch）まで main へ統合予定の状態。T-001〜T-017 は完了済み。
- GitHub open issues / PRs: 0件 (`gh issue list` / `gh pr list` で 2026/07/03 23:01 JST 確認)

## Tasks

| ID | タスク名 | 出典 | 優先度 | 規模 | 状態 |
| --- | --- | --- | --- | --- | --- |
| T-001 | scanner regression test の成功終了コードを明示して WIP 差分を完了する | git status / `tests/scan-private-markers.Tests.ps1` 未コミット差分 | 高 | S | done |
| T-002 | `chore/oss-readiness` をリモートCIで確認し main への取り込み方針を決める | 未mergeブランチ / 引き継ぎ準備 | 中 | S | done |
| T-003 | 引き継ぎ先環境で `pwsh` と README 記載の検証コマンドを確認する | README prerequisite / 引き継ぎ準備 | 低 | S | done |
| T-004 | 必要なら markdown lint または skill validator の導入要否を検討する | README optional validation / 引き継ぎ準備 | 低 | S | done（`docs/VALIDATION_DECISION.md`: 現時点では必須導入せず、任意チェックとして維持。CI追加はゲート①） |
| T-005 | MCP / cloud boundary の公開安全サマリ例を追加する | AGENTS.md §10 / examples拡充候補 | 中 | S | done |
| T-006 | Browser / screenshot / log 境界の公開安全サマリ例を追加する | AGENTS.md §10 / README Synthetic Examples / subagent candidate 2026-06-28 | 中 | S | done |
| T-007 | npm `.npmrc` の literal `_authToken` 値を検出し、環境変数 placeholder は許容する | AGENTS.md §10 / scanner rule expansion candidate 2026-06-28 | 中 | S | done |
| T-008 | 初回release readiness briefとrelease notes draftを準備する | AGENTS.md §10 / release準備候補 | 中 | S | done |
| T-009 | PR #14 後の AGENTS/HANDOFF/TASKS 状態を同期する | git log / 状態同期 | 中 | S | done |
| T-010 | PR #15 後の AGENTS/HANDOFF/TASKS 状態を同期する | git log / 状態同期 | 中 | S | done |
| T-011 | cost approval blocker の公開安全サマリ例を追加する | AGENTS.md §10 / README Synthetic Examples | 中 | S | done |
| T-012 | release / tag gate の公開安全サマリ例を追加する | AGENTS.md §4 / README Synthetic Examples / release readiness brief | 中 | S | done |
| T-013 | GitHub Actions artifact / workflow log 境界の公開安全サマリ例を追加する | AGENTS.md §10 / README Synthetic Examples | 中 | S | done |
| T-014 | PyPI API token prefix を scanner の合成fixtureで検出する | AGENTS.md §10 / scanner rule expansion candidate 2026-07-01 | 中 | M | done |
| T-015 | RubyGems credentials assignment を scanner の合成fixtureで検出する | AGENTS.md §10 / scanner rule expansion candidate 2026-07-01 | 中 | M | done |
| T-016 | GitHub classic token prefix 群を scanner の合成fixtureで検出する | GitHub公式 token prefix / scanner rule expansion candidate 2026-07-02 | 中 | M | done |
| T-017 | GitLab / Hugging Face / Slack webhook / SendGrid marker を scanner の合成fixtureで検出する | docs/REQUIREMENTS_REVIEW_2026-07.md §3 優先度高リスト | 中 | M | done |

- 📌 2026-06-25 Codex 整理: 2026-06-21 の scanner hardening 指摘は PR #4 / commit `aaa8e58` で解決済み。履歴用 docs は公開安全な要約へ圧縮し、ローカル横断索引や旧作業ブランチへの依存は残さない。
- 📌 2026-06-28 Codex 整理: `examples/browser-screenshot-log-summary.md` を追加し、raw screenshot / console / network log を公開報告へ混ぜない合成テンプレートを README / CHANGELOG と同期した。実ブラウザ、実スクリーンショット、外部アップロード、workflow/release/tag は未実行。
- 📌 2026-06-28 Codex 整理: scanner に npm registry `_authToken` 直値の検出と `.npmrc` text scan 対象化を追加した。`${NODE_AUTH_TOKEN}` のような環境変数 placeholder は誤検出しない回帰テストを含む。
- 📌 2026-06-29 Codex 整理: `docs/release-readiness-brief.md` と `docs/release-notes-draft.md` を追加した。tag / GitHub Release / marketplace / package公開は未実行で、version・target commit・timing・notes本文はowner承認待ち。
- 📌 2026-06-30 Codex 整理: PR #14 / merge commit `96e4a95` 後の AGENTS / HANDOFF / TASKS 状態を同期した。GitHub open issue / PR は0件、release/tagは引き続きowner承認待ち。
- 📌 2026-06-30 Codex 整理: PR #15 / merge commit `5d4990a` 後の AGENTS / HANDOFF / TASKS 状態を同期した。GitHub open issue / PR は0件、release/tagは引き続きowner承認待ち。
- 📌 2026-06-30 Codex 整理: `examples/cost-approval-blocker-summary.md` を追加し、paid operationを実行せずに見積・根拠・local/mock代替・承認文言を公開安全に報告する合成例を README / CHANGELOG と同期した。
- 📌 2026-06-30 Codex 整理: `examples/release-tag-gate-summary.md` を追加し、release/tag/workflow/package公開を実行せずにowner承認待ちの停止報告を公開安全に残す合成例を README / CHANGELOG と同期した。
- 📌 2026-07-01 Codex 整理: `examples/github-actions-artifact-boundary-summary.md` を追加し、workflow artifact / job log を公開報告へ混ぜない合成テンプレートを README / CHANGELOG と同期した。実artifact download、workflow変更、release/tagは未実行。

- 📌 2026-07-01 Codex 整理: scanner に PyPI API token prefix の合成検出を追加した。値は redacted のまま、回帰テストは実装前にREDを確認してからGREEN化した。
- 📌 2026-07-01 Codex 整理: scanner に RubyGems credentials assignment の合成検出を追加した。公式docsの credentials key 経路に基づき、直値のみredacted findingにする回帰テストをRED→GREENで追加した。
- 📌 2026-07-02 Codex 整理: scanner に GitHub classic token prefix 群（`ghp_` / `gho_` / `ghu_` / `ghs_` / `ghr_`）の合成検出を追加した。値は redacted のまま、`gho_` / `ghu_` / `ghs_` / `ghr_` はREDを確認してからGREEN化した。
- 📌 2026-07-03 Claude 整理: 上記 GitHub classic token prefix coverage を PR #23 / merge commit `cef69fe` で `main` へ統合し、作業ブランチを削除した。AGENTS / HANDOFF / TASKS を PR #23 後の clean main 状態へ同期した。
- 📌 2026-07-03 Claude 整理: Fable5 の要件再検討メモと市場調査メモを PR #25 で追加した（成功指標のプロセス指標化、scanner 拡充優先度、skill 自体の攻撃面リスク、owner 質問 Q1-Q9、タスク候補 T-017〜T-020 案）。
- 📌 2026-07-03 Claude 整理: T-017 として GitLab / Hugging Face / Slack incoming webhook / SendGrid の合成検出を PR #26 で追加した。実装は Codex GPT-5.5（codex-deep）へ委譲し、RED→GREEN 確認と pwsh 7 実体での再検証（36 tests / 29 files）は Fable5 が実施した。
