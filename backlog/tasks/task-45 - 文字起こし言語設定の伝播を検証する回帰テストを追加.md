---
id: TASK-45
title: 文字起こし言語設定の伝播を検証する回帰テストを追加
status: In Progress
assignee: []
created_date: '2026-07-13 09:27'
updated_date: '2026-07-18 20:24'
labels:
  - Phase2
  - test
dependencies: []
modified_files:
  - Sources/SokkiKit/Transcription/WhisperKitEngine.swift
  - Tests/sokkiTests/Mocks/MockTranscriptionEngine.swift
  - Tests/sokkiTests/TranscriptionPipelineCaptureModeTests.swift
  - Tests/sokkiTests/TranscriptionLanguageTests.swift
  - Tests/sokkiTests/SnapshotTests.swift
priority: medium
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #72（TASK-41）の codex レビュー [MINOR] 指摘からの移送。現状のテストは TranscriptionLanguage の純粋関数のみ検証しており、RecordingView→TranscriptionPipeline→Engine への伝播と、WhisperKitEngine.transcribe() が decodeOptions を実際に wk.transcribe へ渡す配線が未検証。WhisperKitEngine の配線を旧実装に戻しても全テストが通るため、TASK-41 全体が無警告で退行しうる。対応案: MockTranscriptionEngine に setTranscriptionLanguage の記録用プロパティを追加し pipeline.start 経由の伝播テストを追加。あわせて SnapshotTests の RecordingView に .modelContainer が渡っていない点も整える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 設定した言語が TranscriptionPipeline.start 経由で engine.setTranscriptionLanguage に伝播することを検証するテストがある
- [x] #2 WhisperKitEngine の decodeOptions 配線の退行を検知できるテストまたは構造になっている
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 swift build が通る
- [x] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#1: MockTranscriptionEngine に receivedLanguageSettings + setTranscriptionLanguage override を追加し、TranscriptionPipelineCaptureModeTests に「pipeline.start(transcriptionLanguage:) → engine.setTranscriptionLanguage 伝播」テストを2件追加（明示"ja" / 省略時nil）。AC#2: WhisperKitEngine の decodeOptions 生成を単一 seam `currentDecodingOptions()` に集約（transcribe / decodeSegments が共用）し、setTranscriptionLanguage の反映を直接検証する WhisperKitEngineLanguageWiringTests を3件追加（ja固定/auto/既定）。あわせて SnapshotTests の RecordingView 3ケースに .modelContainer(deps.modelContainer) を注入（@Query/modelContext 依存の解消）。swift build 通過、全354テスト中の失敗は既知 Snapshot 4件のみで本変更起因の新規失敗なし。RecordingView Snapshot 3件は変更前から同一環境差で失敗することを stash 比較で確認済み。project.yml 変更なしのため DoD#3 該当なし。
<!-- SECTION:NOTES:END -->
