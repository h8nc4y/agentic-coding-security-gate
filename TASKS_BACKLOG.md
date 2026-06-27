# Tasks Backlog

棚卸し日時: 2026/06/11 20:53:09 JST
最終更新: 2026/06/28 02:02 JST

## Sources

- 既存タスク管理ファイル: 該当なし (`TASKS_BACKLOG.md` / `TODO.md` / `TASKS.md` は未存在)
- README / docs: 明示的な未完了要件は該当なし
- AGENTS.md / `.codex`: リポジトリ内には該当なし
- TODO / FIXME: 該当なし (`rg -n "TODO|FIXME"` で一致なし)
- テスト / lint / 型チェック: `pwsh --version` は `PowerShell 7.6.2` を確認済み。`pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1` と `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1` は成功。lint / 型チェック / build は該当する設定ファイルなし。
- git status: `main` は `origin/main` と一致し、未コミット変更なしで T-003 の作業ブランチを作成。
- GitHub open issues: 0件 (`gh issue list --limit 50 --state open --json number,title,labels,url`)

## Tasks

| ID | タスク名 | 出典 | 優先度 | 規模 | 状態 |
| --- | --- | --- | --- | --- | --- |
| T-001 | scanner regression test の成功終了コードを明示して WIP 差分を完了する | git status / `tests/scan-private-markers.Tests.ps1` 未コミット差分 | 高 | S | done |
| T-002 | `chore/oss-readiness` をリモートCIで確認し main への取り込み方針を決める | 未mergeブランチ / 引き継ぎ準備 | 中 | S | done |
| T-003 | 引き継ぎ先環境で `pwsh` と README 記載の検証コマンドを確認する | README prerequisite / 引き継ぎ準備 | 低 | S | done |
| T-004 | 必要なら markdown lint または skill validator の導入要否を検討する | README optional validation / 引き継ぎ準備 | 低 | S | done（`docs/VALIDATION_DECISION.md`: 現時点では必須導入せず、任意チェックとして維持。CI追加はゲート①） |
| T-005 | MCP / cloud boundary の公開安全サマリ例を追加する | AGENTS.md §10 / examples拡充候補 | 中 | S | done |
| T-006 | Browser / screenshot / log 境界の公開安全サマリ例を追加する | AGENTS.md §10 / README Synthetic Examples / subagent candidate 2026-06-28 | 中 | S | done |

- 📌 2026-06-25 Codex 整理: 2026-06-21 の scanner hardening 指摘は PR #4 / commit `aaa8e58` で解決済み。履歴用 docs は公開安全な要約へ圧縮し、ローカル横断索引や旧作業ブランチへの依存は残さない。
- 📌 2026-06-28 Codex 整理: `examples/browser-screenshot-log-summary.md` を追加し、raw screenshot / console / network log を公開報告へ混ぜない合成テンプレートを README / CHANGELOG と同期した。実ブラウザ、実スクリーンショット、外部アップロード、workflow/release/tag は未実行。
