# HANDOFF

作成日時: 2026/06/21 00:03:17 JST
最終更新: 2026/06/28 01:01 JST

## リポジトリの目的

このリポジトリは、AI coding agent が Git / GitHub / browser / MCP / CLI / cloud / API などの境界を越える前に、secret・private context・real data・paid operation の漏えいや誤実行を防ぐための Codex-style skill を提供する。公開配布向けの `SKILL.md`、合成例、ローカル marker scan、回帰テスト、CI を含む軽量な OSS-ready skill repository である。

## 現状サマリ

- `main` は PR #8 / merge commit `129c24a` まで取り込み済みで、scanner hardening、Anthropic/JWT marker coverage、MCP/cloud boundary example は完了済み。
- private marker scanner は既定で git-tracked files を走査し、ローカル作業メモと CI checkout の対象差を小さくしている。
- `docs/CLAUDE_CODE_REVIEW_2026-06-21.md` と `docs/codex-task-scanner-hardening.md` は、旧レビュー/委譲仕様を公開安全な履歴に圧縮したもの。
- `examples/mcp-cloud-boundary-summary.md` に、MCP / plugin / cloud境界を公開安全に報告する synthetic example を追加済み。
- T-004 は `docs/VALIDATION_DECISION.md` で完了。mandatory markdown lint / external skill validator は現時点では導入せず、任意チェックとして維持する。
- lint / 型チェック / build は該当する設定ファイルがないため未実施扱い。

## 完了タスクと commit

| タスク | commit | 内容 |
| --- | --- | --- |
| OSS readiness 改善 | `19f5e50` | CI、scanner regression tests、contribution/security docs を追加 |
| backlog 棚卸し | `955eff8` | `TASKS_BACKLOG.md` を追加し、残タスクを整理 |
| scanner test 成功終了コード明示 | `4aa3564` | `tests/scan-private-markers.Tests.ps1` の成功時に `exit 0` を追加 |
| scanner hardening | `aaa8e58` | tracked-file scan、credential 形式の検出拡充、text allowlist、best-effort 注記、回帰テストを追加 |
| validation decision | `5bd3d18` | `docs/VALIDATION_DECISION.md` に、mandatory markdown lint / external skill validator は現時点では導入しない判断を記録 |
| Anthropic/JWT marker coverage | `b171619` | private marker scanner と回帰テストへ Anthropic key prefix / compact JWT shape の合成検出を追加 |
| MCP/cloud boundary example | `1782fc6` | `examples/mcp-cloud-boundary-summary.md` を追加し、README / CHANGELOG / backlog / handoff を同期 |

## 未完了 / skip タスク

- T-001〜T-005: done。最新状態は `TASKS_BACKLOG.md` が正本。
- 新しい機能実装・依存追加・リリース自動化は未着手。
- MCP/cloud boundary example は docs-only。実cloud、MCP外部呼び出し、secret、cost operationは未実行。

## 既知の問題・残懸念

- GitHub issue / PR / CI の確認は、通常の sandbox 経路では認証・ネットワーク制約により失敗することがある。必要時は keyring-capable 経路で確認する。
- README / CONTRIBUTING は `pwsh` 7+ を前提としている。Windows PowerShell 5.1 は文書化された互換対象ではない。
- scanner は best-effort であり、全 secret 形式の完全検出を保証しない。公開前の最終判断では Gitleaks/Semgrep などの追加チェックと人間の review を併用する。

## 最終検証結果

実行日時: 2026/06/27 21:23 JST

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| scanner tests | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1` | pass。21 tests passed |
| private marker scan | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1` | pass。tracked mode / 21 files |
| lint | 該当なし | `package.json` 等の lint 設定なし |
| 型チェック | 該当なし | `tsconfig.json` / `pyproject.toml` 等なし |
| build | 該当なし | build 設定なし |

## セットアップ・テスト・ビルド手順

README 記載の推奨環境:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
```

build コマンドは未定義。

## ブランチ状況

- `main`: PR #8 / merge commit `129c24a` まで反映済み。
- この handoff の次回作業では、まず `git status --short --branch` と GitHub の open PR / issue を確認する。

## 次にやるべき候補

1. 公開配布前のrelease/tag準備ブリーフ、または追加scannerルール候補の棚卸しを検討する。
2. release/tag作成とworkflow変更はゲート①のため、実行せずブリーフで停止する。
