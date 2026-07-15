# CODEX_START_HERE — 020_agentic-coding-security-gate

> 全リポジトリ共通の「Codex 引き継ぎの入口」ファイル(2026-07-15 標準化)。
> どのリポジトリでも本ファイルを読めば、正本の所在と着手手順が分かる。

## このリポジトリは何か

AIコーディング時の秘匿情報・危険操作を検知する公開OSSのsecurity gate skill+PowerShellスキャナ。

## 読み順(正本)

1. `README.md` — 概要
2. `docs/REQUIREMENTS.md` — 要件定義(§10 Q1-Q9はオーナー回答待ち)
3. `HANDOFF.md` — 現況・次の一手
4. `TASKS_BACKLOG.md` — タスク台帳
5. `CONTRIBUTING.md` — 攻撃面レビュー指針

## 検証コマンド

`Invoke-Pester tests/scan-private-markers.Tests.ps1 / scripts/scan-private-markers.ps1`

## 主要 gate(承認なしに越えない境界)

- release GOは§10 Q2回答待ち
- スキャナのパターン定義以外にsecretらしき値を書かない

## 次の一手

上記読み順の「現況」資料(HANDOFF 等)の「次の一手」節が正本。本ファイルには時点情報を書かない。

---
運用注記: 開発領域の固定分掌は 2026-07-11 に廃止済み(開発の主軸は Codex、要件・設計・実装・検証・docs を end-to-end で担当)。本ファイルは薄い入口に保ち、現在地・タスクは正本側を更新する。
