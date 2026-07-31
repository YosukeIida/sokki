---
id: TASK-41
title: 文字起こし言語設定を追加
status: Done
assignee: []
created_date: '2026-07-12 12:20'
updated_date: '2026-07-13 09:29'
labels:
  - Phase1
milestone: m-0
dependencies: []
references:
  - Sources/SokkiKit/Transcription/WhisperKitEngine.swift
  - Sources/SokkiKit/UI/SettingsView/SettingsView.swift
  - 'https://github.com/YosukeIida/sokki/issues/63'
priority: medium
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実機E2E確認（TASK-6）で発覚した機能ギャップ。現在 WhisperKitEngine.transcribe は WhisperKit に言語オプションを一切渡しておらず、Whisper側の自動言語判定に完全に依存している。そのため日本語で話しても英語として誤認識される等、言語指定ができない。

WhisperKitの DecodingOptions.language（および必要なら detectLanguage）を設定経由で指定できるようにする。SettingsView に「文字起こし言語」設定（自動検出 / 日本語固定 / 英語固定 等）を追加し、AppSettingsModel に永続化、WhisperKitEngine.transcribe / transcribeStream に配線する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SettingsView に文字起こし言語の設定（自動検出・日本語固定・英語固定等）が追加されている
- [ ] #2 選択した言語が AppSettingsModel に永続化されること
- [ ] #3 WhisperKitEngine が設定された言語を DecodingOptions 経由で WhisperKit に渡し、日本語固定時に実際に日本語として文字起こされること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: 文字起こし言語設定（自動検出/ja/en/zh/ko/es/de/fr）を追加。TranscriptionLanguage 値型 + AppSettingsModel 永続化 + SettingsView UI + TranscriptionEngine protocol に setTranscriptionLanguage（デフォルト no-op でソース互換）+ WhisperKitEngine で DecodingOptions(language:detectLanguage:) 配線。WhisperKit は language: nil だけでは en 固定のため detectLanguage 明示が核心。codex レビュー APPROVE（MINOR 2件: 伝播回帰テストは TASK-45/#97 へ移送、protocol 契約の型付き化は #82 レビューで判断）。PR #72 マージ済み（2026-07-13）。実機検証（日本語固定→日本語認識）はユーザー実施項目。
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:05
---
実装完了・PR #72 マージ可能判定（sonnet 実装・Fable レビュー済み・マージはユーザー承認待ち）。重要な発見: WhisperKit は DecodingOptions(language: nil) だけでは自動検出にならず en 固定になる（detectLanguage 明示が必要）。実機検証（ユーザー）: 日本語固定→録音→日本語認識の確認。マージ後: Done 化 + Issue #63 クローズ。
---
<!-- COMMENTS:END -->
