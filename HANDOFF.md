# HANDOFF

作成日時: 2026/06/12 22:35:33 JST

## リポジトリの目的

このリポジトリは、AI coding agent が Git / GitHub / browser / MCP / CLI / cloud / API などの境界を越える前に、secret・private context・real data・paid operation の漏えいや誤実行を防ぐための Codex-style skill を提供する。現時点の理解では、公開配布向けの `SKILL.md`、合成例、ローカル marker scan、回帰テスト、CI を含む軽量な OSS-ready skill repository である。

## 現状サマリ

- 現在の作業ブランチは `chore/oss-readiness`。
- `main` は `118fba3 feat: add agentic coding security gate skill` を指している。
- `chore/oss-readiness` は OSS readiness 系の変更、backlog、scanner test 修正、handoff 文書を含む未mergeブランチ。
- `TASKS_BACKLOG.md` に doing タスクはない。
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

- `chore/oss-readiness` は未merge。Claude Code 側では、push済みブランチのCI結果と差分を確認して main へ取り込むか判断する。
- 通常の sandbox 経路では `gh issue list` が proxy/network 制約で失敗することがある。権限付き読み取り経路では 2026/06/12 時点で open issues 0 件を確認済み。
- README は `pwsh` を前提としている。今回のローカル検証は Windows PowerShell の `powershell.exe` で実行したため、引き継ぎ先環境で `pwsh` availability を確認する。
- Markdown lint、Skill validator、Gitleaks/Semgrep のリモートCI相当は未追加。必要なら T-004 として検討する。

## 最終検証結果

実行日時: 2026/06/12 22:35 JST

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| scanner tests | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1` | pass。3 tests passed |
| private marker scan | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1` | pass |
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

この Windows host で確認した代替コマンド:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
```

build コマンドは未定義。

## ブランチ状況

- `main`: `118fba3`、`origin/main` と一致。
- `chore/oss-readiness`: 未merge作業ブランチ。`19f5e50`、`955eff8`、`4aa3564` と handoff / backlog closeout commit を含む。この文書が origin 上に存在する場合、その時点で push 済み。
- 未mergeブランチの merge は実施していない。

## 次にやるべき候補

1. `origin/chore/oss-readiness` のCIと差分を確認し、main へ merge するか判断する。
2. 引き継ぎ先環境で `pwsh` と README 記載コマンドがそのまま動くか確認する。
3. 公開配布前に markdown lint または Codex-style skill validator を追加する価値があるか判断する。
