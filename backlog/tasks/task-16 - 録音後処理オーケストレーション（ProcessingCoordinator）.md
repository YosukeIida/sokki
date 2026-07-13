---
id: TASK-16
title: 録音後処理オーケストレーション（ProcessingCoordinator）
status: Done
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-13 11:27'
labels:
  - Phase2
milestone: m-1
dependencies:
  - TASK-14
references:
  - 'https://github.com/YosukeIida/sokki/issues/35'
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ProcessingCoordinator（AsyncStream直列キュー）で 停止→文字起こし→（話者分離）→保存 を体系化する。スリープ復帰・キャンセルに対応する。要約フェーズは省略（Recapのcompleteprocessing WithoutSummary相当）。GitHub Issue #35 (P2-6) 対応。P2-4（リアルタイムストリーミング文字起こし）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ProcessingCoordinatorがAsyncStream直列キューで 停止→文字起こし→（話者分離）→保存 を体系化していること
- [ ] #2 スリープ復帰・キャンセルに対応していること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: ProcessingCoordinator（actor・直列ジョブ実行・PersistentIdentifier 境界設計）による録音後処理オーケストレーションを実装。codex レビューで MAJOR 2件修正（shutdown 時の continuation リーク解放・stop() 再入ガード）→ focused 再レビュー APPROVE。残 MAJOR 2件（captureTask キャンセル伝播・.diarize フェーズ分割）は TASK-25 の diarization 統合時対応として申し送り記録済み。PR #85 マージ済み（2026-07-13）。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:01
---
実装完了・PR #85 マージ可能判定（opus 実装・Fable レビュー・マージ順 #69→#76→#81→#85）。ProcessingCoordinator（@MainActor 直列キュー + 注入 Runner + .diarize 拡張フック）、92テスト。注意: diarization ジョブの実接続は TASK-25 系列マージ時に統合すること。実機検証（ユーザー）: スリープ復帰・終了時部分保存。マージ後: Done 化 + Issue #35 クローズ。
---
<!-- COMMENTS:END -->
