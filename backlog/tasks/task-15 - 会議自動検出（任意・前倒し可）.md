---
id: TASK-15
title: 会議自動検出（任意・前倒し可）
status: Done
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-13 09:39'
labels:
  - Phase2
milestone: m-1
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/34'
documentation:
  - docs/recap-codebase-analysis.md
priority: low
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SCShareableContent（画面収録権限不要）+ bundleID + タイトルパターンでZoom/Teams/Meetを検出し、録音を提案する。参照: recap-codebase-analysis.md 会議検出章。要約非依存で安全に追加可能。GitHub Issue #34 (P2-5) 対応。依存なし（前倒し着手可）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SCShareableContentでZoom/Teams/Meetのウィンドウを検出できること
- [ ] #2 検出時に録音開始をユーザーに提案すること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: SCShareableContent ポーリング（15秒間隔）による会議自動検出を実装。MeetingDetector(actor 的 @Observable) + MeetingDetectionStateMachine（検出/拒否/デバウンス）+ MeetingMatcher/MeetingPattern（Zoom/Teams/Meet、単語境界チェック付きパターンマッチ）+ RecordingView バナー + SettingsView トグル（既定 OFF）。codex レビュー（effort=high）で MAJOR 3件を修正（in-flight poll レース・パターン誤検知・pause/stop 分離による拒否状態維持）、2件反証却下、権限 UI 等は TASK-46/#98 へ移送。#72 との RecordingView コンフリクトは startRecording() 構造維持 + transcriptionLanguage 反映で解消。テスト100件（既知 Snapshot 4件除き全 PASS）。PR #74 マージ済み（2026-07-13）。実機検証: Zoom/Teams/Meet 検出 + 画面収録 TCC 挙動（doc-1 チェックリスト）。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:20
---
実装完了・PR #74 マージ可能判定（sonnet 実装・Fable レビュー済み・マージはユーザー承認待ち）。MeetingDetection/ 新設（Matcher 純粋関数 + 状態機械 + SCShareableContent モック境界）。既定 OFF。実機検証（ユーザー）: Zoom/Teams/Meet での検出→提案バナー。マージ後: Done 化 + Issue #34 クローズ。
---
<!-- COMMENTS:END -->
