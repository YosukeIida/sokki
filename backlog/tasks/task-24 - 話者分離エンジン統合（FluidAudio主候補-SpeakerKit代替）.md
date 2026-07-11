---
id: TASK-24
title: 話者分離エンジン統合（FluidAudio主候補 / SpeakerKit代替）
status: To Do
assignee: []
created_date: '2026-07-11 16:36'
labels:
  - Phase3
milestone: m-3
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/43'
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DiarizationEngine準拠のFluidAudioEngineを追加し、diarizeが実データのDiarizationSegmentを返すようにする。SpeakerKitとprotocolレベルで交換可能な設計を維持する。GitHub Issue #43 (P3-1) 対応。依存なし（Phase3の基盤）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DiarizationEngine準拠のFluidAudioEngineが追加され、diarizeが実データのDiarizationSegmentを返すこと
- [ ] #2 SpeakerKitとprotocolレベルで交換可能であること
<!-- AC:END -->
