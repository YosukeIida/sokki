---
id: TASK-26
title: WhisperKitセグメントとdiarizationのマージ
status: To Do
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-11 16:38'
labels:
  - Phase3
milestone: m-3
dependencies:
  - TASK-24
  - TASK-14
references:
  - 'https://github.com/YosukeIida/sokki/issues/45'
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
時間軸アラインメントで各文字起こしセグメントにspeakerLabelを付与する。参照: WhisperX（〜30行程度の実装規模）。GitHub Issue #45 (P3-3) 対応。P3-1（話者分離エンジン統合）およびP2-4（リアルタイムストリーミング文字起こし）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 時間軸アライメントで各文字起こしセグメントにspeakerLabelが付与されること
<!-- AC:END -->
