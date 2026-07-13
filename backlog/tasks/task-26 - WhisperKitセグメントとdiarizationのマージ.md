---
id: TASK-26
title: WhisperKitセグメントとdiarizationのマージ
status: Done
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-13 13:46'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PR #81 レビューからの引き継ぎ: Both モードは mic/system を到着順インターリーブで1本化しているため、両レーン同時発話時にセグメントタイムスタンプが約2倍に膨らむ（PR 本文明記の MVP 近似）。レーン間順序も withTaskGroup のスケジューリング依存で非決定的。TASK-26 のセグメント×diarization マージ設計時にレーン分離/時間軸正規化とあわせて解消すること。モックエンジンの時間軸検証強化も対で。

PR #87 レビューで診断完了: 時間軸2倍化は SpeakerAlignment ではなくキャプチャ層の問題（本ブランチの .both は micStream スタブで顕在化せず）。根本解消は TASK-52/#105 として独立起票済み（capturedAt ベースのダウンミックス方式・規模M）。

finalSummary: セグメント×diarization を WhisperX 方式の合計交差（SpeakerAlignment.assign 純粋関数）でマージ。1ns 量子化による数値決定性・fillNearest 派生仕様の回帰固定・未割当セグメントの非上書き。codex レビューは BLOCKER/MAJOR ゼロ（MINOR 2件は却下: 量子化は意図的決定性・再ソートは非 hot path）。時間軸2倍化は本 PR スコープ外と診断確定し TASK-52/#105 へ独立起票（capturedAt ダウンミックス方式・SpeakerAlignment 無改修で可）。main 統合で旧 bestOverlapSpeaker を SpeakerAlignment へ一本化。PR #87 マージ済み（2026-07-13）。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:14
---
実装完了・PR #87 マージ可能判定（opus 実装・codex クロスレビュー + 修正・マージ順 #68→#77→#78→#87）。SpeakerAlignment 純粋関数（WhisperX 方式の交差合計割当・決定的タイブレーク・無効区間フィルタ）、87テスト。fillNearest は端点ギャップ距離の派生仕様として明文化。マージ後: Done 化 + Issue #45 クローズ + TASK-29/31/34 解放（着手済み）。
---
<!-- COMMENTS:END -->
