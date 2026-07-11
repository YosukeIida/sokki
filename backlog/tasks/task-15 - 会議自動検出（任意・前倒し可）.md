---
id: TASK-15
title: 会議自動検出（任意・前倒し可）
status: To Do
assignee: []
created_date: '2026-07-11 16:35'
labels:
  - Phase2
milestone: m-1
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/34'
documentation:
  - docs/recap-codebase-analysis.md
priority: low
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SCShareableContent（画面収録権限不要）+ bundleID + タイトルパターンでZoom/Teams/Meetを検出し、録音を提案する。参照: recap-codebase-analysis.md 会議検出章。要約非依存で安全に追加可能。GitHub Issue #34 (P2-5) 対応。依存なし（前倒し着手可）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SCShareableContentでZoom/Teams/Meetのウィンドウを検出できること
- [ ] #2 検出時に録音開始をユーザーに提案すること
<!-- AC:END -->
