---
id: TASK-17
title: TranslationProvider protocol + ルーティング層
status: In Progress
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-12 22:13'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:13
---
実装完了・PR #70 マージ可能判定（opus 実装・codex クロスレビュー2周 + Fable レビュー・マージはユーザー承認待ち）。Translation/ 新設（protocol + Gate + Router + AvailabilityCache + Coordinator）、77テスト。主な設計: 世代トークンで reconcile 再入/teardown 競合を封鎖、missing-key 判定は Gate に一本化、fail-closed 徹底。注意: Gemini Live（TASK-21）は PCM 音声入力のため拡張 protocol が別途必要（レビューで判明、TASK-21 へ移送）。マージ後: Done 化 + Issue #36 クローズ + TASK-18/20/21/22 解放。
---
<!-- COMMENTS:END -->
