---
id: TASK-13
title: レベルメーターUI配線
status: In Progress
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-12 23:16'
labels:
  - Phase2
milestone: m-1
dependencies:
  - TASK-11
references:
  - 'https://github.com/YosukeIida/sokki/issues/32'
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LevelMeterView / WaveformViewにmic=青 / system=赤の実レベルを供給する。system側はdBFSピーク、micもdBFSに統一する。GitHub Issue #32 (P2-3) 対応。P2-1（システム音声キャプチャ）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LevelMeterView / WaveformViewにmic・systemの実レベルが供給されること
- [ ] #2 micとsystem両方が dBFS に統一されていること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:16
---
実装完了・PR #89 マージ可能判定（sonnet・Fable レビュー・マージ順 #69→#76→#81→#89）。既存未配線だった WaveformView への実レベル配線（mic=青/system=赤、.both 2本）、94テスト。dBFS 統一は TASK-11/12 で完了済みだったことを確認。マージ後: Done 化 + Issue #32 クローズ。
---
<!-- COMMENTS:END -->
