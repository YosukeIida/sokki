---
id: TASK-28
title: 話者プロファイル永続化（EMA）セッション横断認識
status: In Progress
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 22:36'
labels:
  - Phase3
milestone: m-3
dependencies:
  - TASK-25
references:
  - 'https://github.com/YosukeIida/sokki/issues/47'
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セッション横断で同一話者を認識できるようにする。SpeakerProfileModelを更新する。GitHub Issue #47 (P3-5) 対応。P3-2（embedding取得配線）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 セッション横断で同一話者を認識できること
- [ ] #2 SpeakerProfileModelがEMAで更新されること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:36
---
実装完了・PR #78 マージ可能判定（sonnet・Fable レビュー済み・マージ順 #68→#77→#78）。EMA 実装は TASK-25 で充足済みと確認し、ストア再オープン横断等の検証テスト 4 件を追加（テストのみの PR）。マージ後: Done 化 + Issue #47 クローズ + TASK-30 解放。
---
<!-- COMMENTS:END -->
