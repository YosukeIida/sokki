---
id: TASK-21
title: GeminiLiveTranslateClient（BYO key・実験的）
status: Done
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-13 16:52'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: GeminiLiveTranslateClient（BYO・実験的・WebSocket）+ PCMConverter を実装。codex レビューで BLOCKER 修正: 既定モデル gemini-2.0-flash-live-001 は 2025-12-09 廃止済み → gemini-3.5-live-translate-preview + 公式スキーマ（translationConfig）に再構築（公式ドキュメント裏付け）。turnComplete 単独フレームのハング・BYO キー漏洩（NSError userInfo の ?key= redact）も修正。setup タイムアウト・マルチターン対応は UI 未到達の実験的コードのため TASK-57/#110 へ移送。PR #86 マージ済み（2026-07-14）。実機検証: BYO キーでの実 API 接続。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:03
---
実装完了・PR #86 マージ可能判定（codex gpt-5.6-sol 実装 + sonnet 検証仕上げ・Fable レビュー・マージ順 #70→#86）。AudioTranslationProviding 拡張 protocol + GeminiLiveTranslateClient（v1alpha WebSocket・PCM 変換・close-first teardown）。sonnet が送信 Task キャンセルの実レースを発見・修正、83テスト。実機検証（ユーザー）: 実 Gemini キーでの接続。UI 配線（実験的表示含む）は TASK-20 後の統合で。マージ後: Done 化 + Issue #40 クローズ。
---
<!-- COMMENTS:END -->
