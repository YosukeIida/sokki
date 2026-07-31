---
id: TASK-13
title: レベルメーターUI配線
status: Done
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-13 11:33'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: mic/system レベルメーターを実レベルに配線（mic=青/system=赤、captureMode 別レーン表示）。rmsLevel→normalize（-60dB..0dB→0..1）+ WaveformView。codex レビューで MAJOR 1件修正（表示専用ストリームの bufferingNewest(1) + UI 側 ~30fps 間引き。ContinuousClock 化も含む）。codex 2周目はタイムアウトで形式判定未取得だが修正はコード検証済み。テスト実効性の MINOR は TASK-48 に追記。PR #89 マージ済み（2026-07-13）。実機検証: 実音声でのメーター表示。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:16
---
実装完了・PR #89 マージ可能判定（sonnet・Fable レビュー・マージ順 #69→#76→#81→#89）。既存未配線だった WaveformView への実レベル配線（mic=青/system=赤、.both 2本）、94テスト。dBFS 統一は TASK-11/12 で完了済みだったことを確認。マージ後: Done 化 + Issue #32 クローズ。
---
<!-- COMMENTS:END -->
