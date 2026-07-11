---
id: TASK-6
title: 録音一覧・詳細画面のE2E動作確認
status: To Do
assignee: []
created_date: '2026-07-11 16:34'
updated_date: '2026-07-11 16:38'
labels:
  - Phase1
  - test
milestone: m-0
dependencies:
  - TASK-4
references:
  - 'https://github.com/YosukeIida/sokki/issues/25'
documentation:
  - docs/handover.md
priority: high
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Xcode ⌘Rで実機動作を確認する：マイク録音→文字起こし→一覧で録音長表示→詳細→セグメント表示まで通し確認。~/Library/Application Support/sokki/recordings/*.m4a の生成も確認する。GitHub Issue #25 (P1-3) 対応。P1-1（音声保存）に依存。現在の再開ポイント（次にやること最優先）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Xcode ⌘Rでマイク録音が開始・停止できること
- [ ] #2 文字起こし結果がSessionDetailに表示されること
- [ ] #3 SessionListに正しい録音長が表示されること
- [ ] #4 録音ファイル（.m4a）がディスクに生成されていることを確認すること
<!-- AC:END -->
