---
id: TASK-8
title: エクスポートにファイル保存ダイアログ + Security-Scoped Bookmark
status: To Do
assignee: []
created_date: '2026-07-11 16:34'
updated_date: '2026-07-11 16:38'
labels:
  - Phase1
milestone: m-0
dependencies:
  - TASK-7
references:
  - 'https://github.com/YosukeIida/sokki/issues/27'
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
クリップボードコピーだけでなく、保存先を選択できるファイル保存ダイアログに対応する。Sandbox下でも再アクセス可能なようSecurity-Scoped Bookmarkを実装する。GitHub Issue #27 (P1-5) 対応。P1-4（Markdownエクスポート確認）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 NSSavePanel等でユーザーが保存先を選択できること
- [ ] #2 Sandbox環境下でSecurity-Scoped Bookmarkにより再アクセスできること
<!-- AC:END -->
