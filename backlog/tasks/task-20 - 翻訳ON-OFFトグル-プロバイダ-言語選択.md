---
id: TASK-20
title: 翻訳ON/OFFトグル + プロバイダ/言語選択
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
  - 'https://github.com/YosukeIida/sokki/issues/39'
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SettingsViewと録音画面トグルを実装する。OFF時はクラウド送信ゼロにする。プライバシーモード時はisOnDevice==falseのプロバイダを抑止する。GitHub Issue #39 (P25-4) 対応。P25-1（TranslationProvider protocol）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SettingsViewと録音画面に翻訳トグルがあること
- [ ] #2 OFF時はクラウド送信がゼロであること
- [ ] #3 プライバシーモード時はisOnDevice==falseのプロバイダが抑止されること
<!-- AC:END -->
