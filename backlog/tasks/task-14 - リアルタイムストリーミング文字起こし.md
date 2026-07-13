---
id: TASK-14
title: リアルタイムストリーミング文字起こし
status: In Progress
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-12 22:38'
labels:
  - Phase2
milestone: m-1
dependencies:
  - TASK-11
references:
  - 'https://github.com/YosukeIida/sokki/issues/33'
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WhisperKit v1.0のstreaming/確定境界APIを実機確認し、現状の擬似窓実装を置換または確定境界を実装する。Hypothesis（灰）/ Confirmed（黒）2系統表示にする。参照: WhisperAXサンプル。GitHub Issue #33 (P2-4) 対応。P2-1（システム音声キャプチャ）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 WhisperKit v1.0 の streaming/確定境界 API を実機確認し、現状の擬似窓実装を置換または確定境界を実装する
- [ ] #2 Hypothesis（灰色表示）/ Confirmed（黒表示）の2系統表示が動作すること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:38
---
実装完了・PR #76 マージ可能判定（opus 実装・codex クロスレビュー + 修正対応・Fable レビュー・マージ順 #69→#76）。WhisperKit AudioStreamTranscriber の確定境界アルゴリズムを ConfirmedBoundaryTracker（純粋値型）として再実装、Hypothesis（灰）/Confirmed（黒） 2系統表示、75テスト。既知の制約: 全サンプルバッファ保持（約3.84MB/分、前方トリムは将来課題）。実機検証（ユーザー）: 両モードの遷移品質・レイテンシ・長時間メモリ。マージ後: Done 化 + Issue #33 クローズ + TASK-16/19/26/35 解放（35 は着手済み）。
---
<!-- COMMENTS:END -->
