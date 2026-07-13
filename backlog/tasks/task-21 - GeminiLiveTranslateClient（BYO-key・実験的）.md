---
id: TASK-21
title: GeminiLiveTranslateClient（BYO key・実験的）
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-12 23:03'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-17
references:
  - 'https://github.com/YosukeIida/sokki/issues/40'
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
URLSessionWebSocketTask + PCMConverter（Float32→Int16）を実装する。字幕はinput/outputAudioTranscriptionから取得する。プレビュー扱いの注意表示を行う。GitHub Issue #40 (P25-5) 対応。P25-1（TranslationProvider protocol）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 URLSessionWebSocketTask + PCMConverter（Float32→Int16）が実装されていること
- [ ] #2 input/outputAudioTranscriptionから字幕が取得できること
- [ ] #3 UI上で「実験的機能（プレビュー）」と明示されていること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:03
---
実装完了・PR #86 マージ可能判定（codex gpt-5.6-sol 実装 + sonnet 検証仕上げ・Fable レビュー・マージ順 #70→#86）。AudioTranslationProviding 拡張 protocol + GeminiLiveTranslateClient（v1alpha WebSocket・PCM 変換・close-first teardown）。sonnet が送信 Task キャンセルの実レースを発見・修正、83テスト。実機検証（ユーザー）: 実 Gemini キーでの接続。UI 配線（実験的表示含む）は TASK-20 後の統合で。マージ後: Done 化 + Issue #40 クローズ。
---
<!-- COMMENTS:END -->
