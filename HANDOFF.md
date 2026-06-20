# HANDOFF

作成日時: 2026/06/21 00:03:17 JST

## リポジトリの目的

このリポジトリは、AI coding agent が Git / GitHub / browser / MCP / CLI / cloud / API などの境界を越える前に、secret・private context・real data・paid operation の漏えいや誤実行を防ぐための Codex-style skill を提供する。現時点の理解では、公開配布向けの `SKILL.md`、合成例、ローカル marker scan、回帰テスト、CI を含む軽量な OSS-ready skill repository である。

## 現状サマリ

- `main` は `origin/main` と一致し、T-003 の文書整合は merge 済み。
- 作業ブランチは残っていない。
- `TASKS_BACKLOG.md` に doing タスクはない。T-003 は `pwsh` 可用性と README 記載コマンドの確認として完了。
- open GitHub issues は 0 件。
- TODO / FIXME コメントは見つかっていない。
- この締め作業では新機能実装・リファクタ・依存追加は行っていない。
- lint / 型チェック / build は該当する設定ファイルがないため未実施扱い。

## 完了タスクと commit

| タスク | commit | 内容 |
| --- | --- | --- |
| OSS readiness 改善 | `19f5e50` | CI、scanner regression tests、contribution/security docs を追加 |
| backlog 棚卸し | `955eff8` | `TASKS_BACKLOG.md` を追加し、残タスクを整理 |
| scanner test 成功終了コード明示 | `4aa3564` | `tests/scan-private-markers.Tests.ps1` の成功時に `exit 0` を追加 |

## 未完了 / skip タスク

- skip タスクはなし。
- 未完了候補は `TASKS_BACKLOG.md` の T-002 から T-004 を参照。

## 既知の問題・残懸念

- 通常の sandbox 経路では `gh issue list` が proxy/network 制約で失敗することがある。権限付き読み取り経路では 2026/06/20 時点で open issues 0 件を確認済み。
- README / CONTRIBUTING は `pwsh` 7+ を前提としている。Windows PowerShell 5.1 は文書化された互換対象ではない。
- Markdown lint、Skill validator、Gitleaks/Semgrep のリモートCI相当は未追加。必要なら T-004 として検討する。

## 最終検証結果

実行日時: 2026/06/20 23:34 JST

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| pwsh availability | `pwsh --version` | pass。PowerShell 7.6.2 |
| scanner tests | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1` | pass。3 tests passed |
| private marker scan | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1` | pass |
| lint | 該当なし | `package.json` 等の lint 設定なし |
| 型チェック | 該当なし | `tsconfig.json` / `pyproject.toml` 等なし |
| build | 該当なし | build 設定なし |
| GitHub issues | `gh issue list --limit 50 --state open --json number,title,labels,url` | pass。0件 |

## セットアップ・テスト・ビルド手順

README 記載の推奨環境:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
```

build コマンドは未定義。

## ブランチ状況

- `main`: `origin/main` と一致。
- `docs/pwsh-runtime-clarity`: PR #2 で merge 済み、remote branch は削除済み。

## 次にやるべき候補

1. 公開配布前に markdown lint または Codex-style skill validator を追加する価値があるか判断する（採用時の CI 変更は承認ゲート対象）。
2. スキャナの検出ルール拡充や合成 example 追加を小さく進める。
