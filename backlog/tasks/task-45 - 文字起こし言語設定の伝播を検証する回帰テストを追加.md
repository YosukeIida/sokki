---
id: TASK-45
title: 文字起こし言語設定の伝播を検証する回帰テストを追加
status: To Do
assignee: []
created_date: '2026-07-13 09:27'
updated_date: '2026-07-13 09:28'
labels:
  - Phase2
  - test
dependencies: []
priority: medium
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #72（TASK-41）の codex レビュー [MINOR] 指摘からの移送。現状のテストは TranscriptionLanguage の純粋関数のみ検証しており、RecordingView→TranscriptionPipeline→Engine への伝播と、WhisperKitEngine.transcribe() が decodeOptions を実際に wk.transcribe へ渡す配線が未検証。WhisperKitEngine の配線を旧実装に戻しても全テストが通るため、TASK-41 全体が無警告で退行しうる。対応案: MockTranscriptionEngine に setTranscriptionLanguage の記録用プロパティを追加し pipeline.start 経由の伝播テストを追加。あわせて SnapshotTests の RecordingView に .modelContainer が渡っていない点も整える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 設定した言語が TranscriptionPipeline.start 経由で engine.setTranscriptionLanguage に伝播することを検証するテストがある
- [ ] #2 WhisperKitEngine の decodeOptions 配線の退行を検知できるテストまたは構造になっている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/97
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
