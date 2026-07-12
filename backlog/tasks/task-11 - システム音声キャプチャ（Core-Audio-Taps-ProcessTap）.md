---
id: TASK-11
title: システム音声キャプチャ（Core Audio Taps / ProcessTap）
status: To Do
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-12 18:58'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
【TASK-10 決定を踏まえた注記・2026-07-13】無署名/ad-hoc 署名ビルドでは Core Audio Taps の TCC prompt（NSAudioCaptureUsageDescription）が発火しない可能性が高いという実体験報告が複数ある（Apple公式の明文規定は未確認）。実装自体は無署名でも進められるが、実機での動作確認は Developer ID 署名 or 安定した signing identity が無いと成立しない可能性がある。着手時は早い段階で無署名ビルドでの TCC prompt 発火有無を実機確認し、発火しない場合は Developer ID 取得のタイミングをこのタスクの前提条件として扱うこと。
<!-- SECTION:NOTES:END -->
