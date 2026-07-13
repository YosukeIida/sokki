---
id: TASK-30
title: SpeakerProfileView UI（名前編集・声紋削除）
status: In Progress
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 22:57'
labels:
  - Phase3
milestone: m-3
dependencies:
  - TASK-28
references:
  - 'https://github.com/YosukeIida/sokki/issues/49'
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
プロファイル一覧・名前編集・出現回数表示・削除機能のUIを実装する。GitHub Issue #49 (P3-7) 対応。P3-5（話者プロファイル永続化）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 プロファイル一覧・名前編集・出現回数・削除ができること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:57
---
実装完了・PR #83 マージ可能判定（sonnet 実装・Fable レビュー・マージ順 #68→#77→#78→#83）。インライン名前編集・削除 UI 配線（.nullify 検証付き）・出現回数/最終出現表示・SpeakerColorBar 再利用、70テスト。実機検証（ユーザー）: RenderPreview での見た目。マージ後: Done 化 + Issue #49 クローズ。
---
<!-- COMMENTS:END -->
