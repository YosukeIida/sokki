---
id: TASK-36
title: プライバシーモード切替UI + ローカル/APIインジケーター
status: To Do
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-11 16:38'
labels:
  - Phase5
milestone: m-5
dependencies:
  - TASK-20
references:
  - 'https://github.com/YosukeIida/sokki/issues/55'
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既定ONとし、状態を録音画面に明示する。isOnDevice==falseのプロバイダの抑止と連動させる。GitHub Issue #55 (P5-1) 対応。P25-4（翻訳ON/OFFトグル + プロバイダ/言語選択）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 プライバシーモードが既定ONであること
- [ ] #2 録音画面にローカル/APIの状態が明示されること
- [ ] #3 isOnDevice==falseのプロバイダの抑止と連動すること
<!-- AC:END -->
