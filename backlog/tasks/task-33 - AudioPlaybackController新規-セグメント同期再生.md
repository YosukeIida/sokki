---
id: TASK-33
title: AudioPlaybackController新規 + セグメント同期再生
status: In Progress
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 22:24'
labels:
  - Phase4
milestone: m-4
dependencies:
  - TASK-4
references:
  - 'https://github.com/YosukeIida/sokki/issues/52'
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セグメントクリックで該当時刻から再生できるようにする（FR-DATA-3）。保存済み音声ファイルが前提となる。GitHub Issue #52 (P4-2) 対応。P1-1（録音音声のディスク保存）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AudioPlaybackControllerが新規実装されること
- [ ] #2 セグメントクリックで該当時刻から再生できること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:24
---
実装完了・PR #75 マージ可能判定（sonnet 実装・Fable レビュー済み・#73 のスタック PR。マージ順: #73→#75）。Playback/AudioPlaybackController 新設 + 再生バー + セグメント同期再生・ハイライト。実機検証（ユーザー）: 再生/シーク/ハイライト、.m4a の load。マージ後: Done 化 + Issue #52 クローズ。TASK-43（直列③）は RecordingView 等で #74 とも競合するため、マージ後の着手を推奨。
---
<!-- COMMENTS:END -->
