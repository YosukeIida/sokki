---
id: TASK-16
title: 録音後処理オーケストレーション（ProcessingCoordinator）
status: To Do
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-11 16:38'
labels:
  - Phase2
milestone: m-1
dependencies:
  - TASK-14
references:
  - 'https://github.com/YosukeIida/sokki/issues/35'
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ProcessingCoordinator（AsyncStream直列キュー）で 停止→文字起こし→（話者分離）→保存 を体系化する。スリープ復帰・キャンセルに対応する。要約フェーズは省略（Recapのcompleteprocessing WithoutSummary相当）。GitHub Issue #35 (P2-6) 対応。P2-4（リアルタイムストリーミング文字起こし）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ProcessingCoordinatorがAsyncStream直列キューで 停止→文字起こし→（話者分離）→保存 を体系化していること
- [ ] #2 スリープ復帰・キャンセルに対応していること
<!-- AC:END -->
