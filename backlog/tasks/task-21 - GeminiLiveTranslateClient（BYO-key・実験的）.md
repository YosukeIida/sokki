---
id: TASK-21
title: GeminiLiveTranslateClient（BYO key・実験的）
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
  - 'https://github.com/YosukeIida/sokki/issues/40'
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
URLSessionWebSocketTask + PCMConverter（Float32→Int16）を実装する。字幕はinput/outputAudioTranscriptionから取得する。プレビュー扱いの注意表示を行う。GitHub Issue #40 (P25-5) 対応。P25-1（TranslationProvider protocol）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 URLSessionWebSocketTask + PCMConverter（Float32→Int16）が実装されていること
- [ ] #2 input/outputAudioTranscriptionから字幕が取得できること
- [ ] #3 UI上で「実験的機能（プレビュー）」と明示されていること
<!-- AC:END -->
