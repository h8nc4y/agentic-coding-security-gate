# Requirements Review 2026-07

作成日: 2026/07/03
作成者: ClaudeCode Fable5（引き継ぎレビュー）。GPT-5.5（相談役）の批判的レビュー所見を 2026/07/03 に反映済み。
位置づけ: 既存要件（`AGENTS.md` §1・`README.md`・`SKILL.md`・`docs/VALIDATION_DECISION.md`・`docs/release-readiness-brief.md`）を前提にした再検討メモ。製品要件そのものの変更はゲート④（owner承認）であり、本書は判断材料と質問の整理までを行う。

## 1. 確認済み事実と未確認事項

### 確認済み（local git / GitHub CLI / repo 内資料で裏取り済み）

- `main` は PR #24 まで統合済み。T-001〜T-016 完了。open issue / PR は 0 件（2026/07/03 確認）。
- Git tag / GitHub Release は未作成。release readiness brief / notes draft は準備済みで、version・target commit・timing・notes 本文が owner 承認待ち（ゲート①）。
- 品質ゲートは scanner 回帰テスト（30 tests）＋ marker scan（tracked mode）で、ローカル・CI とも緑。
- scanner のカバー範囲: OpenAI / Anthropic / GitHub（classic 5 prefix + fine-grained）/ Slack（bot・user・app）/ AWS access key id / GCP API key / Stripe live key / JWT 形状 / PEM ブロック / bearer ヘッダ / npm・PyPI・RubyGems のレジストリ credential / email / Windows 絶対パス / 私的リポジトリ・パス marker / 許可リスト外 GitHub URL。
- 配布形態は手動インストール（Codex-style skills ディレクトリへ `SKILL.md` をコピー）。npm / Marketplace 公開は Non-Goal。

### 未確認（本書では前提にしない）

- 外部ユーザーによる採用・利用実績（未確認。導線が存在しないため実質ゼロと推定。stars 0 を確認）。
- 他エージェント（Claude Code 等）環境で SKILL.md ゲートが実際に遵守されるかの実地検証。
- 競合・代替ツールの最新の機能範囲・無料枠（`docs/fable5-market-research-2026-07.md` で補完。陳腐化を前提に扱う）。

## 2. 価値仮説の再検討

### 2.1 このプロダクトの本体は何か

本 skill の構成要素は (a) SKILL.md による行動境界ゲート、(b) PowerShell 製 marker scanner、(c) 合成例テンプレート群、の3つ。再検討の結論として、**本体価値は (a) と (c)** にあると判断する。ただし (b) は単なる「補助」ではない: SKILL.md は行動規範であって実行を強制できないため、scanner は**唯一の決定的・回帰可能な検証レイヤ**として (a) の信用を支える（相談役レビュー指摘 #1）。

設計原則の追加（相談役レビュー指摘 #8）: 本 skill は高性能エージェントを前提にしない。**弱い・忘れる・注入され得るエージェントでも破綻しにくい境界設計**（fail-safe 側に倒れる規範、機械検証可能なゲート）を要件の軸とする。

- secret 検出そのもの（(b)）は、Gitleaks / TruffleHog / GitHub push protection という強力な既存手段があり、単体では勝負にならない。scanner は「この repo 自身のドッグフーディング品質ゲート」および「skill 利用者向けの最小限のローカル補助」と位置づけるのが正しい。
- 一方、(a)+(c) がカバーする「公開 issue/PR へ貼る前の redact 規律」「課金・release・credential 境界での停止」「証拠ベース報告（not checked の明示）」は、secret scanner では代替できない **エージェントの行動規範レイヤ** であり、既存ツールとの差別化点。
- 市場調査（2026-07、`docs/fable5-market-research-2026-07.md`）の結論もこれを支持する: エージェント経由の secret 漏えい / prompt injection 経由 exfiltration は 2025-2026 に実インシデントが多発しており問題設定の必然性は裏付けられる一方、同一射程（境界越え直前のプリフライトゲート skill）の競合は確認されなかった。secret scanning 三層（Gitleaks / TruffleHog / platform 層）およびベンダー公式ガードレール（permission modes / sandbox / approval）とは補完関係にある。

### 2.2 利用者は誰か

- **一次利用者は owner 自身のマルチエージェント開発環境**（Codex / Claude Code が並走する複数リポジトリ）。ここでのインシデント防止・ドッグフーディングが現在の実証済み価値。
- 外部利用者（他の agentic coding 実践者）は潜在層。ただし release / 発見導線が無い現状では到達不能であり、外部価値は未検証のまま。

### 2.3 成功指標の候補（owner 確認待ち）

「インシデント 0 件の継続」は分母がなく、偶然の 0 と効果の 0 を区別できないため主指標にしない（相談役レビュー指摘 #2）。プロセス指標を主とする:

| 区分 | 指標案 | 計測方法 |
| --- | --- | --- |
| 主 | ゲート発火の記録: 境界越え前に停止・redact した near-miss 件数（redact 済みで記録） | 各 repo の dev log / boundary summary 例の実運用数 |
| 主 | scanner の既知 false positive / false negative の棚卸しと回帰テスト化率 | 本 repo の tests / backlog |
| 主 | 本 repo の品質ゲート（tests + scan + CI）緑の維持 | CI 履歴 |
| 副 | 初回 release 公開の完了（ゲート①承認後） | GitHub Release の存在 |
| 副 | 品質を伴う外部採用: 第三者が scanner・合成例を実行し公開安全な issue / PR を作れた事例 | GitHub issue / PR の内容 |

## 3. スキャナ拡充の限界効用と次の投資先

token prefix の追加は T-014〜T-016 で3連続しており、限界効用は逓減局面に入りつつある。残る高価値ターゲットは「エージェント開発で実際に触りやすいサービス」の credential 形式に絞るべき:

- 優先度高: GitLab personal access token、Hugging Face token、Slack incoming webhook URL、SendGrid API key（いずれも公式に文書化された固定 prefix / URL 形状があり、誤検出リスクが低い）。
- 中優先（文脈検出が必要）: Google OAuth client secret は prefix 単独ではなく credential file / JSON field の文脈で検出すべき（相談役レビュー指摘 #3）。owner 環境での実利用文脈に応じて Cloudflare / Vercel / Netlify 系も候補（DigitalOcean より優先度を上げる余地あり）。
- 優先度低（誤検出リスク高・prefix 不定）: Azure 系接続文字列、Discord bot token、汎用 hex/base64 エントロピー検出。エントロピー検出は Gitleaks 等の守備範囲であり本 scanner では行わない。
- 設計方針（相談役レビュー指摘 #4）: prefix 一本槍にせず、既存の npm / RubyGems ルールと同様に **URL・HTTP header・JSON key・代入文・既知 credential file 名を組み合わせた文脈付きルール**を基本形とする。prefix が変わり得る形式（GitLab self-managed 等）ほど文脈側で拾う。

scanner 拡充と並行して、次の投資先候補は以下（優先順に）:

1. **初回 release の owner 承認取得**（version / target commit / timing / notes 本文）。発見可能性の前提条件。
2. **OSS 受け入れ整備**: `CODE_OF_CONDUCT.md`、Issue / PR テンプレート（`.github/` 配下だが workflow ではないためゲート①対象外と判断。ただし初回追加時に owner へ一言確認するのが安全）。
3. **adversarial decision matrix**: 「SKILL.md の実効性証明」を謳うとモデル・システム指示・読み込み順・ツール権限で結果が変わるため疑似科学になる（相談役レビュー指摘 #5）。範囲を限定し、合成シナリオごとに期待判断（stop / redact / synthetic / not checked のいずれか）を表形式で定義した静的な decision matrix として整備する。エージェント実測は「参考情報」の位置づけに留める。
4. **対応プラットフォームの拡張**（Claude Code の skills 形式への対応など）: 対応プラットフォーム変更はゲート④に該当するため、owner 判断待ちの質問として提示する（§5 Q3）。

## 3.5 中心リスク: 本 skill 自体が攻撃面になる可能性

相談役レビュー指摘 #6 を受けて中心リスクに格上げする。SKILL.md はエージェントにとって高信頼の指示文であるため、悪意ある PR・隠し Unicode 文字・遠隔参照指示・過剰権限への誘導が混入した場合の被害は通常の OSS より大きい。対応方針:

- SKILL.md / examples への変更 PR は、diff の全文レビュー＋hidden character 検査を必須とする（レビュー観点として `CONTRIBUTING.md` への明文化を検討）。
- SKILL.md に「外部 URL の指示を取得して従う」類の remote instruction を含めない方針を維持・明文化する。
- release 前チェックリスト（`docs/release-readiness-brief.md`）に「skill scanner（SkillSpector 等）による検査結果または未実施の明記」を加えることを検討。
- 本 repo の marker scanner は「公開安全の軽量ガード」であり、skill scanner や GitHub secret scanning の**代替ではない**ことを README で引き続き明示する（相談役レビュー指摘 #10）。

## 4. Non-Goals の再確認

`README.md` の Non-Goals（Release 自動化 / Marketplace / package 公開 / cloud setup / 有料 API 実行なし）は、ゼロ依存・公開安全という製品性格と整合しており **維持を推奨**。変更が必要になる兆候（例: 配布摩擦が採用の主障壁になる等）が出た時点でゲート④として再提起する。

## 5. Owner への質問リスト

| # | 区分 | 質問 |
| --- | --- | --- |
| Q1 | 目的・利用者 | 第一目的は「owner 環境の実用ガード」の維持でよいか。外部採用（stars / 利用者獲得）をどの程度優先するか。 |
| Q2 | release | 初回 release の GO 判断: version（brief 案は 0.1.0 相当）、target commit、公開タイミング、notes 本文の承認。 |
| Q3 | 公開範囲 | Claude Code など Codex 以外のエージェントへの導入手順をスコープに入れるか（対応プラットフォーム変更＝ゲート④）。 |
| Q4 | スコープ | scanner の prefix 拡充はどこまで続けるか。§3 の優先度高リストで一区切りとし、以降は Gitleaks 等の併用推奨に委ねる方針でよいか。 |
| Q5 | 費用上限 | 引き続き無料枠のみ（GitHub free + ローカル実行）でよいか。有料の secret scanning / SAST 連携は Non-Goal のままとするか。 |
| Q6 | 配布導線 | ワンコマンド skill インストーラ（`npx skills add` 系）経由の導入案内を README に載せるか。Non-Goals の「Marketplace packaging」との整合判断（ゲート④）。市場調査では手動コピー限定は露出面の主障壁と示唆された。 |
| Q7 | 運用定義 | incident / near-miss の定義と記録方法（§2.3 の主指標の前提）。どこまでを「ゲート発火」として数えるか。 |
| Q8 | 摩擦許容度 | fail-closed（疑わしきは止める）による作業摩擦をどこまで許容するか。誤停止が多い場合に緩める判断基準。 |
| Q9 | 信頼モデル | release 後、利用者は「どの commit / tag を信頼してよいか」をどう判断するか（tag 署名・checksum・release notes の検証手順の要否）。 |

## 6. 直近のタスク候補（backlog へ反映する前の案）

| 候補 | 内容 | ゲート |
| --- | --- | --- |
| T-017 案 | scanner rule 拡充バッチ（優先度高: GitLab PAT / Hugging Face token / Slack webhook URL / SendGrid。文脈付きルールを基本形、合成 fixture・RED→GREEN・値は redacted） | なし |
| T-018 案 | `CODE_OF_CONDUCT.md` と Issue / PR テンプレート追加 | なし（初回のみ owner へ念のため確認） |
| T-019 案 | adversarial decision matrix（合成シナリオ × 期待判断 stop/redact/synthetic/not-checked の静的表）の整備 | なし（docs のみ） |
| T-020 案 | skill 自体の攻撃面対策: CONTRIBUTING へ hidden character 検査・remote instruction 禁止のレビュー観点を明文化 | なし |
| — | 初回 release 実行 | ゲート①（owner 承認必須） |
