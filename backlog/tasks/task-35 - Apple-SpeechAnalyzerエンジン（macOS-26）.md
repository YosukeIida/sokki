---
id: TASK-35
title: Apple SpeechAnalyzerエンジン（macOS 26+）
status: In Progress
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 22:53'
labels:
  - Phase4
milestone: m-4
dependencies:
  - TASK-14
references:
  - 'https://github.com/YosukeIida/sokki/issues/54'
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TranscriptionEngine準拠でドロップイン評価する。参照: swift-scribe（GitHub 上の SpeechAnalyzer 実装例リポジトリ）。GitHub Issue #54 (P4-4) 対応。P2-4（リアルタイムストリーミング文字起こし）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TranscriptionEngine準拠でSpeechAnalyzerエンジンをドロップイン評価できること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:53
---
実装完了・PR #82 マージ可能判定（opus 実装・Fable レビュー・マージ順 #69→#76→#82）。SpeechAnalyzerEngine（macOS 26+、@available ガード + WhisperKit フォールバック）+ エンジン選択 Picker、85テスト。マージ時の統合メモ: #72 の setTranscriptionLanguage protocol メソッドに揃える小整理が必要。実機評価（ユーザー）: ja-JP モデル DL・品質/レイテンシの WhisperKit 比較。マージ後: Done 化 + Issue #54 クローズ。
---
<!-- COMMENTS:END -->
