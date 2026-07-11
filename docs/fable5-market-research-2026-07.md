# Market Research Memo 2026-07

作成日: 2026/07/03
作成者: ClaudeCode Fable5（Web 調査は subagent に委譲し、本書はその要約）
位置づけ: `docs/REQUIREMENTS.md` §2（課題と価値仮説）の根拠資料。Web 由来の情報は陳腐化し得るため、引用時は再確認すること。外部 GitHub リポジトリの URL は本 repo の公開安全ルールにより記載せず、名称のみで参照する。

## 1. 競合・代替手段の現状（2026年時点）

### Secret scanning 系（隣接領域・補完関係）

- Gitleaks / TruffleHog / detect-secrets はいずれも OSS・無料。2026 年の定番は「Gitleaks（pre-commit/CI 高速スキャン）＋ TruffleHog（履歴・credential 有効性検証）＋ GitHub Secret Scanning / Push Protection（プラットフォーム層、無料枠あり）」の三層併用。
- これらは「コミット済み secret の事後検知」が中心。**本 skill の射程（エージェントが境界を越える直前に止めるプリフライトゲート）とは検出タイミングが異なり、直接競合ではなく補完関係**。

### エージェント公式ガードレール系

- Claude Code: permission modes ＋ PreToolUse hooks ＋ OS レベル sandboxing ＋ auto mode（分類器による承認委任）＋ 組み込み security review（正規表現チェック＋LLM diff レビューの多層構成）。
- Codex CLI: sandbox / approval モデル（バイパスは明示フラグの CI 限定運用）。
- いずれも**ベンダー公式のランタイム防御**であり、本 skill の「ポータブルな行動規範＋公開前 redact 規律＋証拠ベース報告」はこれらが拾わない層を補完する。

### Agent skill エコシステム

- SKILL.md 形式は Anthropic 公式仕様。2026 年時点で複数の skill marketplace が存在し、主要 3 marketplace だけで 49 万件超の skill が流通。
- skill を検査する scanner（NVIDIA SkillSpector、Cisco skill-scanner 等）は存在するが、2026-06 に全 scanner をすり抜けた偽 skill が約 26,000 エージェントに到達した事件が報告された。skill 収集研究では収集 skill の約 26% が何らかの脆弱パターンを含むとの報告もある（一次論文は未確認）。
- **本 skill と同一射程（境界越え防止特化のプリフライトゲート skill）は本調査では確認できなかった**（ニッチ＝差別化余地。ただし市場実証は未確認）。

## 2. エージェント経由の漏えいインシデント実態（2025-2026）

報告例（要約ベース、個別の一次確認は未実施）:

- 2025-06: Microsoft 365 Copilot でゼロクリック prompt injection によるデータ流出。
- 2026-02: Cline の npm publish 事件（AI issue トリアージ × CI シェル × キャッシュポイズニングの連鎖で publish credential が悪用）。
- 2026 年: GitHub Copilot の PR 説明文経由 prompt injection で RCE となる CVE（CVSS 9.6）報告。
- 2026-03: 悪意ある MCP サーバーが実績を積んだ後に exfiltration コードを追加していた事件。
- 2026-04: 複数の coding agent への同時 prompt injection 攻撃の報告。

→ 「エージェント経由の secret 漏えい / exfiltration」は実在する多発脅威であり、**本 skill の問題設定の必然性は市場的に裏付けられる**。ただし本 skill が特定インシデントを防いだという一次証拠はない（未確認）。

## 3. skill 配布の標準的方法

- 手動コピー以外の主流は `npx skills add <owner>/<repo>` 形式のワンコマンドインストーラ（vercel-labs の skills CLI、2026-01 ローンチ）。Claude Code / Codex CLI / Cursor 等を横断してインストール可能。
- marketplace 掲載には SKILL.md 形式準拠＋メタデータの体裁要件があり、scanner 通過が事実上の掲載前提になりつつある。
- 本 repo は GitHub 上の公開リポジトリであるため、追加作業なしでも `npx skills add` の対象になり得る可能性があるが、動作は未確認。README での案内可否は Non-Goals（Marketplace packaging）との整合を owner が判断する（ゲート④）。

## 4. OSS 採用の成功要因（README・CI・バッジ以外）

- 初速の stars が検索・Trending 露出の循環を生む（最初の数十 star が重要）。
- 「5 秒で伝わる価値訴求」: README 冒頭の具体例・図解がバッジ羅列より効く。
- 実運用実績の訴求: 「どの運用でどんな漏えいを防いだか」の公開安全な事例。現状は synthetic examples のみで実績訴求が弱い。
- ワンコマンド導入の参入障壁の低さが採用速度に直結。

## 5. 本 skill への示唆（要約）

1. 問題設定（境界越え直前ゲート）は実インシデントに裏付けられ、同一射程の競合は未確認。ポジショニングは有効。
2. secret 検出は既存三層（Gitleaks/TruffleHog/platform）との補完を明示し、scanner 単体で勝負しない現方針を維持。
3. 露出の最大障壁は配布導線。release 未作成・手動コピー限定・stars 0 の現状では外部到達はほぼ不可能。初回 release（ゲート①）とワンコマンド導入可否の判断（ゲート④）が次のボトルネック。
4. ゼロ依存・ローカル完結の設計は、skill scanner の信頼性問題を踏まえると「検査可能で安全な skill」という訴求材料になる。
