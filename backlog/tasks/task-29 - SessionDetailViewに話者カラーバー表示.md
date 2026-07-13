---
id: TASK-29
title: SessionDetailViewに話者カラーバー表示
status: In Progress
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 23:16'
labels:
  - Phase3
milestone: m-3
dependencies:
  - TASK-26
references:
  - 'https://github.com/YosukeIida/sokki/issues/48'
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
詳細画面の左端に話者カラーを表示し、話者ごとに色分けする。GitHub Issue #48 (P3-6) 対応。P3-3（WhisperKitセグメントとdiarizationのマージ）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SessionDetailViewの左端に話者カラーが表示されること
- [ ] #2 話者ごとに色分けされること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:16
---
実装完了・PR #88 マージ可能判定（sonnet・Fable レビュー・マージ順 #68→#77→#78→#87→#88）。SpeakerColorBar 配線 + Color(hex:) 共通化 + モック準拠レイアウト、87テスト。注意: スナップショットは実機で要再記録の可能性。マージ後: Done 化 + Issue #48 クローズ。
---
<!-- COMMENTS:END -->
