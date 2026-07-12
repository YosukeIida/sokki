---
id: TASK-34
title: ファイルインポート（.mp4/.m4a/.wav/.mp3）
status: To Do
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-11 16:38'
labels:
  - Phase4
milestone: m-4
dependencies:
  - TASK-26
references:
  - 'https://github.com/YosukeIida/sokki/issues/53'
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AudioFileImporterを実装し、既存ファイルを文字起こし・話者分離できるようにする。GitHub Issue #53 (P4-3) 対応。P3-3（WhisperKitセグメントとdiarizationのマージ）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AudioFileImporterが.mp4/.m4a/.wav/.mp3を取り込めること
- [ ] #2 取り込んだファイルが文字起こし・話者分離されること
<!-- AC:END -->
