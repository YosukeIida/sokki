---
id: TASK-18
title: AppleTranslationProvider（既定・オンデバイス）★実機PoC先行
status: To Do
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-11 16:38'
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
