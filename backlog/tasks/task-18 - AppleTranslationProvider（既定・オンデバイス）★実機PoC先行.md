---
id: TASK-18
title: AppleTranslationProvider（既定・オンデバイス）★実機PoC先行
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-12 23:15'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-17
references:
  - 'https://github.com/YosukeIida/sokki/issues/37'
documentation:
  - docs/translation-architecture.md
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
macOS 15 Translation Frameworkで確定セグメントを翻訳する。.translationTask制約に対応した供給経路を実装する。19言語対応、モデルダウンロードプロンプト対応。実機PoCを先行させる位置づけ。GitHub Issue #37 (P25-2) 対応。P25-1（TranslationProvider protocol）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 macOS 15 Translation Frameworkで確定セグメントを翻訳できること
- [ ] #2 .translationTask制約に対応した供給経路が実装されていること
- [ ] #3 モデル未ダウンロード時にダウンロードプロンプトが出ること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:15
---
実装完了・PR #80（opus 実装・codex クロスレビュー + 修正・マージ順 #70→#80）。他の PR と異なり **マージは実機 PoC 成功が前提条件**: (1) .translationTask closure 常駐 drain の成立 (2) 0pt ホストからのモデル DL 同意 UI 表示（Fallback 案は PR 本文）(3) ja↔en 実翻訳。Bridge は世代 ID + レジストリ + once-guard の状態機械、95テスト。PoC 成功後: マージ + Done 化 + Issue #37 クローズ + TASK-19 解放。
---
<!-- COMMENTS:END -->
