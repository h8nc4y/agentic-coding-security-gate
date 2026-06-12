# Tasks Backlog

棚卸し日時: 2026/06/11 20:53:09 JST
最終更新: 2026/06/12 22:35:33 JST

## Sources

- 既存タスク管理ファイル: 該当なし (`TASKS_BACKLOG.md` / `TODO.md` / `TASKS.md` は未存在)
- README / docs: 明示的な未完了要件は該当なし
- AGENTS.md / `.codex`: リポジトリ内には該当なし
- TODO / FIXME: 該当なし (`rg -n "TODO|FIXME"` で一致なし)
- テスト / lint / 型チェック: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1` は成功、`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1` は成功。lint / 型チェック / build は該当する設定ファイルなし。
- git status: `chore/oss-readiness` 上の未コミット変更は backlog / handoff の締めcommitへ整理。
- GitHub open issues: 0件 (`gh issue list --limit 50 --state open --json number,title,labels,url`)

## Tasks

| ID | タスク名 | 出典 | 優先度 | 規模 | 状態 |
| --- | --- | --- | --- | --- | --- |
| T-001 | scanner regression test の成功終了コードを明示して WIP 差分を完了する | git status / `tests/scan-private-markers.Tests.ps1` 未コミット差分 | 高 | S | done |
| T-002 | `chore/oss-readiness` をリモートCIで確認し main への取り込み方針を決める | 未mergeブランチ / 引き継ぎ準備 | 中 | S | todo |
| T-003 | 引き継ぎ先環境で `pwsh` と README 記載の検証コマンドを確認する | README prerequisite / 引き継ぎ準備 | 低 | S | todo |
| T-004 | 必要なら markdown lint または skill validator の導入要否を検討する | README optional validation / 引き継ぎ準備 | 低 | S | todo |
