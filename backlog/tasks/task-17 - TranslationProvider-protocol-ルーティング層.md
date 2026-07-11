---
id: TASK-17
title: TranslationProvider protocol + ルーティング層
status: To Do
assignee: []
created_date: '2026-07-11 16:35'
labels:
  - Phase2.5
milestone: m-2
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/36'
documentation:
  - docs/translation-architecture.md
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
protocol（isOnDevice / supports(source:target:) / translateStream）とTranslationCoordinator（Tier1 Apple → Tier2 BYOの自動ルーティング + プライバシーゲート）を実装する。参照: docs/translation-architecture.md。GitHub Issue #36 (P25-1) 対応。依存なし（翻訳系タスクの基盤）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TranslationProvider protocol（isOnDevice / supports(source:target:) / translateStream）が定義されていること
- [ ] #2 TranslationCoordinatorがTier1 Apple→Tier2 BYOの自動ルーティングとプライバシーゲートを実装していること
<!-- AC:END -->
