---
id: TASK-53
title: ファイルインポートのガードレール（メモリ・排他制御・実データ fixture）
status: To Do
assignee: []
created_date: '2026-07-13 12:51'
updated_date: '2026-07-13 12:52'
labels:
  - Phase4
dependencies: []
priority: low
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #91（TASK-34）の codex レビューからの移送。(1) インポート音声を全量 [Float] で保持するメモリ使用量（MAJOR 残存分。WhisperKitEngine.transcribe(audioArray:) がバッチ全量 API のため、チャンク化はバッチ API 再設計を伴う。録音由来 diarization も同方式のため共通課題）。(2) 録音中（pipeline.isRunning）でもインポートを開始できる排他制御の欠如（actor 直列化でクラッシュはしないが、インポートが録音終了まで待たされる UX 問題。アプリ全体の状態調停が必要）。(3) mp4 音声抽出・実 mp3 経路の実データ fixture テスト整備。(4) UUID 先頭8文字のファイル名衝突リスク（既存挙動・低確率）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 大容量ファイルのインポートでメモリ使用量が有界になっている（またはサイズ上限ガードがある）
- [ ] #2 録音中のインポート開始が制御されている（ブロック or キュー + UI 表示）
- [ ] #3 mp4/mp3 実データ fixture のテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/106
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
