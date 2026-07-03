# HANDOFF

作成日時: 2026/06/21 00:03:17 JST
最終更新: 2026/07/03 23:45 JST

## リポジトリの目的

このリポジトリは、AI coding agent が Git / GitHub / browser / MCP / CLI / cloud / API などの境界を越える前に、secret・private context・real data・paid operation の漏えいや誤実行を防ぐための Codex-style skill を提供する。公開配布向けの `SKILL.md`、合成例、ローカル marker scan、回帰テスト、CI を含む軽量な OSS-ready skill repository である。

## 現状サマリ

- `main` は PR #26 まで取り込み済みで、scanner hardening、Anthropic/JWT marker coverage、MCP/cloud boundary example、browser/screenshot/log boundary example、npm auth-token scanner coverage、release readiness brief / notes draft、state sync、cost approval blocker example、release/tag gate example、GitHub Actions artifact boundary example、PyPI / RubyGems / GitHub classic token / GitLab / Hugging Face / Slack webhook / SendGrid の scanner coverage、Fable5 要件レビュー docs は完了済み。現時点で Git tag / GitHub Release は存在しない。
- private marker scanner は既定で git-tracked files を走査し、ローカル作業メモと CI checkout の対象差を小さくしている。
- `docs/CLAUDE_CODE_REVIEW_2026-06-21.md` と `docs/codex-task-scanner-hardening.md` は、旧レビュー/委譲仕様を公開安全な履歴に圧縮したもの。
- `examples/mcp-cloud-boundary-summary.md` に、MCP / plugin / cloud境界を公開安全に報告する synthetic example を追加済み。
- `examples/browser-screenshot-log-summary.md` に、browser / screenshot / console / network log境界を公開安全に報告する synthetic example を追加済み。
- `examples/cost-approval-blocker-summary.md` に、paid operationを実行せず見積・根拠・local/mock代替・承認文言を公開安全に報告する synthetic example を追加。
- `examples/release-tag-gate-summary.md` に、release / tag / workflow / package公開を実行せずowner承認待ちの停止報告を公開安全に残す synthetic example を追加。
- `examples/github-actions-artifact-boundary-summary.md` に、GitHub Actions artifact / job log 境界を公開安全に報告する synthetic example を追加済み。
- `scripts/scan-private-markers.ps1` に PyPI API token prefix の合成検出を追加し、`tests/scan-private-markers.Tests.ps1` で RED → GREEN を確認済み。
- `scripts/scan-private-markers.ps1` に RubyGems credentials assignment の合成検出を追加し、`tests/scan-private-markers.Tests.ps1` で RED → GREEN を確認済み。
- `scripts/scan-private-markers.ps1` に GitHub classic token prefix 群（`ghp_` / `gho_` / `ghu_` / `ghs_` / `ghr_`）の合成検出を追加し、`tests/scan-private-markers.Tests.ps1` で `gho_` / `ghu_` / `ghs_` / `ghr_` の RED → GREEN を確認済み。
- `scripts/scan-private-markers.ps1` に GitLab PAT / Hugging Face token / Slack incoming webhook URL / SendGrid API key 2セグメント形状の合成検出を追加（T-017、実装は codex-deep 委譲・Fable5 レビュー）。誤検出防止のネガティブテスト2件を含み RED → GREEN を確認済み。
- GitLab coverage は 2026-07-02 の Codex ローカル WIP ブランチを回収・統合し、公式 token overview table の prefix family（personal / deploy / runner / CI job / trigger / feed / incoming mail / agent / workspace / SCIM / feature flags）と session cookie 形状へ拡張済み。狭い glpat 単独ルールは広い family ルールへ置換した。
- `docs/REQUIREMENTS_REVIEW_2026-07.md`（要件再検討、owner 質問 Q1-Q9、タスク候補 T-017〜T-020 案）と `docs/fable5-market-research-2026-07.md`（市場調査）を追加済み。owner の回答待ち事項はこの2文書を正とする。
- T-004 は `docs/VALIDATION_DECISION.md` で完了。mandatory markdown lint / external skill validator は現時点では導入せず、任意チェックとして維持する。
- lint / 型チェック / build は該当する設定ファイルがないため未実施扱い。
- 初回release readiness briefとrelease notes draftを追加済み。tag push / GitHub Release作成 / version・target commit・公開タイミング・notes本文承認は未実施。

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
| Browser/screenshot/log boundary example | `ff59c59` | `examples/browser-screenshot-log-summary.md` を追加し、README / CHANGELOG / backlog / handoff を同期 |
| npm auth-token scanner coverage | `de3ee1d` | `.npmrc` text scan と literal `_authToken` assignment の検出回帰を追加 |
| release readiness brief / notes draft | `607b712` | 初回owner-approved release向けの承認前ブリーフとnotes draftを追加 |
| PR #14 後の状態同期 | `7cbd74c` / PR #15 merge `5d4990a` | AGENTS / HANDOFF / TASKS を PR #14 後の clean main 状態へ同期 |
| PR #15 後の状態同期 | `a3e2a3f` / PR #16 merge `9a8c3b3` | AGENTS / HANDOFF / TASKS を PR #15 後の clean main 状態へ同期 |
| Cost approval blocker example | `1d1a086` / PR #17 merge `ae6bcce` | paid operation前の停止報告をsynthetic exampleとして追加 |
| Release/tag gate example | `docs/release-tag-gate-summary-example` | release/tag公開前の停止報告をsynthetic exampleとして追加 |
| GitHub Actions artifact boundary example | `docs/ci-artifact-boundary-summary` | workflow artifact / job logを公開報告へ貼らないsynthetic summaryを追加 |
| PyPI token scanner coverage | PR #20 / `98891d5` | PyPI API token prefix の synthetic fixture 検出を追加 |
| RubyGems credentials scanner coverage | PR #21 / `68c4bfe` | RubyGems credentials assignment の synthetic fixture 検出を追加 |
| GitHub classic token scanner coverage | PR #23 / `cef69fe` | GitHub classic token prefix 群の synthetic fixture 検出を追加 |
| Fable5 要件レビュー / 市場調査 docs | PR #25 / `b594cff` | 要件再検討メモと市場調査メモを追加 |
| GitLab/HF/Slack webhook/SendGrid scanner coverage | PR #26 | T-017 の4形式 synthetic fixture 検出を追加 |

## 未完了 / skip タスク

- T-001〜T-016: done。最新状態は `TASKS_BACKLOG.md` が正本。
- 新しい機能実装・依存追加・リリース自動化は未着手。release readiness brief / notes draft はdocs-onlyで追加済み。
- MCP/cloud boundary example は docs-only。実cloud、MCP外部呼び出し、secret、cost operationは未実行。

## 既知の問題・残懸念

- GitHub issue / PR / CI の確認は、通常の sandbox 経路では認証・ネットワーク制約により失敗することがある。必要時は keyring-capable 経路で確認する。
- README / CONTRIBUTING は `pwsh` 7+ を前提としている。Windows PowerShell 5.1 は文書化された互換対象ではない。
- scanner は best-effort であり、全 secret 形式の完全検出を保証しない。公開前の最終判断では Gitleaks/Semgrep などの追加チェックと人間の review を併用する。
- 2026-06-28 の npm auth-token assignment 拡充により、tracked/worktree の `.npmrc` 内に `_authToken=` の直値があれば検出し、`${NODE_AUTH_TOKEN}` のような環境変数 placeholder は許容する。
- 2026-07-01 の PyPI prefix 拡充により、`pypi-` から始まる token-length suffix の合成fixtureを検出する。
- 2026-07-01 の RubyGems credentials 拡充により、credentials file の API key直値を検出する。
- 2026-07-02 の GitHub classic token prefix 拡充により、`ghp_` / `gho_` / `ghu_` / `ghs_` / `ghr_` から始まる token-like suffix の合成fixtureを検出する。
- 2026-07-03 の T-017 拡充により、GitLab PAT prefix / Hugging Face token prefix / Slack incoming webhook URL / SendGrid 2セグメント key 形状の合成fixtureを検出する。prefix が変わり得る形式は今後文脈付きルールで補完する方針（`docs/REQUIREMENTS_REVIEW_2026-07.md` §3）。

## 最終検証結果

実行日時: 2026/07/04 00:15 JST

| 種別 | コマンド | 結果 |
| --- | --- | --- |
| scanner tests | `pwsh -NoProfile -File .\tests\scan-private-markers.Tests.ps1` | pass。48 tests passed（pwsh 7 で実行） |
| private marker scan | `pwsh -NoProfile -File .\scripts\scan-private-markers.ps1` | pass。tracked mode / 29 files |
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

- `main`: PR #26 まで反映済み。マージ済み作業ブランチは削除済み。
- 作業ブランチ: 無し。
- この handoff の次回作業では、まず `git status --short --branch` と GitHub の open PR / issue を確認する。現在の release/tag はowner承認待ちで、実行はゲート①。

## 次にやるべき候補

1. owner が `docs/REQUIREMENTS_REVIEW_2026-07.md` §5 の質問 Q1-Q9 に回答する（release GO 判断の Q2 を含む）。
2. release/tag作成とworkflow変更はゲート①のため、実行せずブリーフまたは `examples/release-tag-gate-summary.md` の形式で停止する。
3. owner 回答を待つ間の自走候補: T-018（CODE_OF_CONDUCT / Issue・PR テンプレート）、T-019（adversarial decision matrix）、T-020（CONTRIBUTING へ skill 攻撃面対策のレビュー観点明文化）。詳細は要件レビュー §6。
