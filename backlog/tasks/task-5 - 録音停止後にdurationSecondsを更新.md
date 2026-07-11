---
id: TASK-5
title: 録音停止後にdurationSecondsを更新
status: Done
assignee: []
created_date: '2026-07-11 16:34'
updated_date: '2026-07-11 17:37'
labels:
  - Phase1
milestone: m-0
dependencies:
  - TASK-4
references:
  - 'https://github.com/YosukeIida/sokki/issues/24'
  - 'commit:48f75f5'
modified_files:
  - Sources/SokkiKit/Transcription/TranscriptionPipeline.swift
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
停止時にSessionManager.updateDuration（既存API）を呼び、一覧・詳細画面に正しい録音長を表示する。GitHub Issue #24 (P1-2) 対応。P1-1（録音音声のディスク保存）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 録音停止時にSessionManager.updateDurationが呼ばれること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
旧 AC#2（SessionList / SessionDetail での録音長表示確認）は TASK-6 の E2E 確認（AC#3）に一本化した（重複解消・2026-07-12）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TranscriptionPipelineで録音URLを渡し、stop時にdurationSecondsを更新するよう配線。GitHub #24は実装済みだが未クローズ。
<!-- SECTION:FINAL_SUMMARY:END -->
