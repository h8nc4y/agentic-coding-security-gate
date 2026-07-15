# 要件定義書 — agentic-coding-security-gate

最終更新: 2026/07/12
位置づけ: 本書がプロダクト要件の**正本**。要件そのものの変更（スコープ・公開範囲・skill の振る舞い・Non-Goals・ライセンス・対応プラットフォーム）は `AGENTS.md` §4 ゲート④（owner 承認）に該当する。本書は 2026-07 の要件再検討メモと validation 採否判断を統合し、それらを置き換える（経緯は git 履歴の `docs/REQUIREMENTS_REVIEW_2026-07.md` / `docs/VALIDATION_DECISION.md` を参照）。

## 1. プロダクト定義

AI coding agent が Git / GitHub issue・PR / ブラウザ / MCP / CLI / クラウド / API の**境界を越える直前**に、secret・私的コンテキスト・実データ・課金操作の漏えい・誤実行を止めるための、公開配布前提のポータブルな「セキュリティゲート」skill。

- 成果物: `SKILL.md`（本体）＋ `examples/`（合成例）＋ `scripts/scan-private-markers.ps1`（marker scanner）＋ `tests/`（回帰テスト）＋ CI。
- ランタイム: PowerShell 7+（`pwsh`）と Markdown のみ。ゼロ依存。ライセンス: MIT。
- 配布: 手動インストール（`SKILL.md` を skills ディレクトリへコピー）。

## 2. 課題と価値仮説

エージェント経由の secret 漏えい / prompt injection 経由 exfiltration は 2025-2026 に実インシデントが多発しており、問題設定の必然性は市場的に裏付けられる（根拠: `docs/fable5-market-research-2026-07.md`。Web 由来情報は陳腐化前提で再確認する）。同一射程（境界越え直前のプリフライトゲート skill）の競合は 2026-07 調査では未確認。

構成要素の価値は次の通り:

- **本体価値 = (a) SKILL.md の行動境界規範 ＋ (c) 合成例テンプレート**。「公開 issue/PR へ貼る前の redact 規律」「課金・release・credential 境界での停止」「証拠ベース報告（not checked の明示）」は secret scanner では代替できない行動規範レイヤであり、差別化点。
- **(b) marker scanner は唯一の決定的・回帰可能な検証レイヤ**として (a) の信用を支える。secret 検出単体では Gitleaks / TruffleHog / GitHub push protection と勝負しない。既存三層およびベンダー公式ガードレール（permission modes / sandbox / approval）とは補完関係。

## 3. 利用者

- **一次利用者**: owner 自身のマルチエージェント開発環境（Codex / Claude Code が並走する複数リポジトリ）。ここでのインシデント防止・ドッグフーディングが実証済み価値。
- **潜在利用者**: 外部の agentic coding 実践者。release / 発見導線が無い現状では到達不能で、外部価値は未検証。

## 4. 設計原則

1. **弱いエージェントでも破綻しない境界設計**: 高性能エージェントを前提にしない。忘れる・注入され得るエージェントでも fail-safe 側に倒れる規範と、機械検証可能なゲートを軸にする。
2. **ゼロ依存・ローカル完結**: 検査可能で安全な skill であること自体を訴求材料にする。
3. **公開安全のドッグフーディング**: 本 repo 自身の PR・docs・examples にも skill のルール（redact・合成・証拠ベース）を適用し、marker scanner を常に緑に保つ。
4. **決定的ゲート優先**: skill 本文は行動規範であり実行を強制できない。強制が必要な部分は scanner・CI・レビュー規約（`CONTRIBUTING.md`）側に置く。

## 5. スコープ

### In scope

- SKILL.md の境界ゲート規範と合成例（`examples/`、新しい境界シナリオは合成データのみで追加）。
- marker scanner の拡充。**基本形は文脈付きルール**（URL・HTTP header・JSON key・代入文・既知 credential file 名の組み合わせ）とし、prefix 単独ルールは公式に固定 prefix が文書化され誤検出リスクが低い形式に限る。
- 期待判断の静的参照表（`docs/adversarial-decision-matrix.md`）。エージェント実測による実効性証明は謳わない。

### Out of scope（scanner）

- エントロピー検出・汎用 hex/base64 検出（Gitleaks 等の守備範囲）。
- prefix 不定で誤検出リスクが高い形式（Azure 接続文字列、Discord bot token 等）の prefix 単独検出。

### 拡充の優先度（2026-07 時点）

prefix 追加は T-014〜T-017 で限界効用が逓減。次の候補は文脈検出が必要な形式（Google OAuth client secret の credential file 文脈、owner 実利用に応じて Cloudflare / Vercel / Netlify 系）。継続可否は owner 未決事項 Q4 による。

## 6. Non-Goals

`README.md` の Non-Goals と同一（Release 自動化 / Marketplace packaging / package 公開 / cloud setup / 有料 API 実行なし）。変更はゲート④として再提起する。

## 7. 成功指標

「インシデント 0 件の継続」は分母がなく効果と偶然を区別できないため主指標にしない。プロセス指標を主とする:

| 区分 | 指標 | 計測方法 |
| --- | --- | --- |
| 主 | ゲート発火の記録: 境界越え前に停止・redact した near-miss 件数（redact 済みで記録） | 各 repo の dev log / boundary summary の実運用数 |
| 主 | scanner の既知 false positive / negative の棚卸しと回帰テスト化率 | 本 repo の tests / backlog |
| 主 | 品質ゲート（tests + scan + CI）緑の維持 | CI 履歴 |
| 副 | 初回 release 公開の完了（ゲート①承認後） | GitHub Release の存在 |
| 副 | 品質を伴う外部採用事例 | GitHub issue / PR の内容 |

## 8. 中心リスク: skill 自体が攻撃面になること

SKILL.md はエージェントにとって高信頼の指示文であり、悪意ある変更（隠し Unicode・remote instruction・過剰権限への誘導）の被害は通常の OSS より大きい。対策は実装済み:

- `CONTRIBUTING.md` "Skill Content Review (Attack Surface)": 全 diff 逐行レビュー、hidden-unicode 検査、remote-instruction 拒否、ゲート弱体化誘導の拒否。
- `docs/adversarial-decision-matrix.md` の期待判断を覆す変更は要件変更（ゲート④）として扱う。
- scanner は敵対的指示文を検出しない。skill scanner（SkillSpector 等）や GitHub secret scanning の代替ではないことを README で明示し続ける。

## 9. 品質ゲートと検証方針

必須ゲートは次の 2 コマンド（CI も `windows-latest` で同一実行）:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ./tests/scan-private-markers.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/scan-private-markers.ps1
```

- mandatory markdown lint / 外部 skill validator は**採用しない**（ゼロ依存・軽量配布方針と不整合。CI 追加はゲート①）。任意チェック（markdown lint、Gitleaks、Semgrep、skill validator）は環境にあれば実行してよいが、実行したものだけを報告する。
- 再検討トリガ: release/tag・marketplace 型配布の準備開始、安定した local skill validator の選定、markdown 整形ノイズがレビューを阻害、CI 方針変更の明示承認。
- release 直前の追加検証は `docs/release-readiness-brief.md` を正とする。

## 10. Owner 未決事項（回答待ち）

| # | 区分 | 質問 |
| --- | --- | --- |
| Q1 | 目的・利用者 | 第一目的は「owner 環境の実用ガード」の維持でよいか。外部採用をどの程度優先するか。 |
| Q2 | release | 初回 release の GO 判断: version（brief 案 0.1.0 相当）、target commit、公開タイミング、notes 本文の承認。 |
| Q3 | 公開範囲 | Claude Code など Codex 以外のエージェントへの導入手順をスコープに入れるか（ゲート④）。 |
| Q4 | スコープ | scanner 拡充の継続範囲。§5 の方針（文脈付きルール中心）で一区切りとし、以降は Gitleaks 等の併用推奨に委ねるか。 |
| Q5 | 費用上限 | 引き続き無料枠のみ（GitHub free + ローカル実行）でよいか。 |
| Q6 | 配布導線 | ワンコマンド skill インストーラ経由の導入案内を README に載せるか（Non-Goals との整合、ゲート④）。手動コピー限定は露出面の主障壁と市場調査が示唆。 |
| Q7 | 運用定義 | incident / near-miss の定義と記録方法（§7 主指標の前提）。 |
| Q8 | 摩擦許容度 | fail-closed による作業摩擦の許容範囲。誤停止が多い場合に緩める判断基準。 |
| Q9 | 信頼モデル | release 後、利用者が信頼してよい commit / tag の判断方法（署名・checksum・検証手順の要否）。 |

## 11. 関連文書

| 文書 | 役割 |
| --- | --- |
| `SKILL.md` / `examples/` | 製品本体（英語・公開向け） |
| `docs/adversarial-decision-matrix.md` | 期待判断の静的参照表 |
| `docs/fable5-market-research-2026-07.md` | §2 の根拠資料（2026-07 時点、陳腐化前提） |
| `docs/release-readiness-brief.md` / `docs/release-notes-draft.md` | 初回 release のゲート①承認資料 |
| `AGENTS.md` | 開発運用コントラクト（自走ループ・4ゲート） |
| `HANDOFF.md` / `TASKS_BACKLOG.md` | 現況とタスクの正本 |
