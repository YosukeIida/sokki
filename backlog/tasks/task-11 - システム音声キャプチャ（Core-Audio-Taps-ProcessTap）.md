---
id: TASK-11
title: システム音声キャプチャ（Core Audio Taps / ProcessTap）
status: To Do
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-11 16:38'
labels:
  - Phase2
milestone: m-1
dependencies:
  - TASK-10
references:
  - 'https://github.com/YosukeIida/sokki/issues/30'
documentation:
  - docs/recap-codebase-analysis.md
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AudioCaptureManagerにProcessTapを内包し、systemStream / systemLevelStreamを配線する。startCapture(.systemOnly)のthrowを解除する。参照: docs/recap-codebase-analysis.md §0+本文（WhisperKit/entitlementの訂正に注意）。GitHub Issue #30 (P2-1) 対応。P2-0（配布方針決定）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AudioCaptureManagerにProcessTapを内包し、systemStream / systemLevelStreamを配線する
- [ ] #2 startCapture(.systemOnly)がthrowしなくなり、実際にシステム音声がキャプチャできること
<!-- AC:END -->
