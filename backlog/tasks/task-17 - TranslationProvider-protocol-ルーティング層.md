---
id: TASK-17
title: TranslationProvider protocol + ルーティング層
status: Done
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-13 16:47'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: TranslationProvider protocol + ルーティング層（TranslationRouter/TranslationCoordinator/TranslationGate/AvailabilityCache）を実装。Apple オンデバイス既定 / BYO API 代替のハイブリッド方針の基盤。codex レビュー（effort=high）で BLOCKER 2件修正: 世代奪還レース（requestSeq 化・修正前 fail の回帰テスト付き）+ prepare 中 provider の即時 close。pump 所有権・Gate 監査タグ（DI 誤注入の fail-closed 化）も修正。残余（appleProvider lease 化・overlapping teardown 契約・isCloudActive 更新順序）は real provider 結線の前提条件として TASK-18 に申し送り済み — ユーザー音声のクラウド送信ゼロ保証自体は破れないことを検証済み。PR #70 マージ済み（2026-07-14）。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:13
---
実装完了・PR #70 マージ可能判定（opus 実装・codex クロスレビュー2周 + Fable レビュー・マージはユーザー承認待ち）。Translation/ 新設（protocol + Gate + Router + AvailabilityCache + Coordinator）、77テスト。主な設計: 世代トークンで reconcile 再入/teardown 競合を封鎖、missing-key 判定は Gate に一本化、fail-closed 徹底。注意: Gemini Live（TASK-21）は PCM 音声入力のため拡張 protocol が別途必要（レビューで判明、TASK-21 へ移送）。マージ後: Done 化 + Issue #36 クローズ + TASK-18/20/21/22 解放。
---
<!-- COMMENTS:END -->
