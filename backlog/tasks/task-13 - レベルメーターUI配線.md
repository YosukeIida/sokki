---
id: TASK-13
title: レベルメーターUI配線
status: To Do
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-11 16:38'
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
