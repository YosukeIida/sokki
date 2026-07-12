---
id: TASK-19
title: 翻訳字幕UI（2レーン + フローティング）
status: To Do
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-11 16:38'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-18
  - TASK-14
references:
  - 'https://github.com/YosukeIida/sokki/issues/38'
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
録音中に原文/訳文の2レーン表示を行う。会議横のフローティングオーバーレイ（NSPanel, sharingType=.noneで画面共有に映り込まない）を実装する。GitHub Issue #38 (P25-3) 対応。P25-2（AppleTranslationProvider）およびP2-4（リアルタイムストリーミング文字起こし）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 録音中に原文/訳文の2レーン表示が動作すること
- [ ] #2 NSPanelでsharingType=.noneのフローティングオーバーレイが画面共有に映り込まないこと
<!-- AC:END -->
