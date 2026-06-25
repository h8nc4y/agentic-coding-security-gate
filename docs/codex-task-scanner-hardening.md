# Codex タスク履歴: private marker scanner hardening

このファイルは、2026-06-21 に作成された scanner hardening 委譲タスクを、解決済み履歴として公開安全に要約したものです。元の委譲文にはローカル環境名と秘匿値検出用の具体例が含まれていたため、現在の版では公開 PR に不要な具体値を省いています。

## 目的

private marker scanner を、ローカル作業ツリーでも CI でも再現しやすく、より多くの代表的 credential 形式を redaction 前提で検出できるようにする。

## 実装済み

- 既定 scan mode を git-tracked files に寄せ、未追跡のローカル作業メモで scan が失敗する状態を避けた。
- git が使えない worktree fallback では agent-local scratch dirs を除外するようにした。
- text extension allowlist を導入し、画像などのバイナリ拡張子を line scan しないようにした。
- 代表的なクラウド・SaaS credential 形式、private-key block、Bearer header、placeholder email の検出・redaction 回帰テストを追加した。
- scanner 自身のファイル名を blanket exempt にせず、marker-like value は script path 内でも検出する契約を維持した。
- `SKILL.md` / `SECURITY.md` に best-effort scan の限界を明記した。

## 完了条件と現在地

- PR #4 / commit `aaa8e58` で main に merge 済み。
- 2026-06-25 の Codex ローカル確認では、scanner tests は 19 ケース pass、private marker scan は tracked mode で pass。
- 旧作業ブランチやローカル横断索引を参照する追加手順は不要。

## 未完了

- markdown lint または skill validator の導入判断は T-004 として未着手。追加する場合も、依存・CI 変更がこの skill の軽量配布方針と合うかを先に確認する。
