---
id: TASK-26
title: WhisperKitセグメントとdiarizationのマージ
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-12 23:14'
labels:
  - Phase3
milestone: m-3
dependencies:
  - TASK-24
  - TASK-14
references:
  - 'https://github.com/YosukeIida/sokki/issues/45'
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
時間軸アラインメントで各文字起こしセグメントにspeakerLabelを付与する。参照: WhisperX（〜30行程度の実装規模）。GitHub Issue #45 (P3-3) 対応。P3-1（話者分離エンジン統合）およびP2-4（リアルタイムストリーミング文字起こし）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 時間軸アライメントで各文字起こしセグメントにspeakerLabelが付与されること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:14
---
実装完了・PR #87 マージ可能判定（opus 実装・codex クロスレビュー + 修正・マージ順 #68→#77→#78→#87）。SpeakerAlignment 純粋関数（WhisperX 方式の交差合計割当・決定的タイブレーク・無効区間フィルタ）、87テスト。fillNearest は端点ギャップ距離の派生仕様として明文化。マージ後: Done 化 + Issue #45 クローズ + TASK-29/31/34 解放（着手済み）。
---
<!-- COMMENTS:END -->
