---
id: TASK-48
title: システム音声キャプチャの hardening + テスト拡充（IOProc 分離・変換 status 検証・IO ブリッジテスト）
status: To Do
assignee: []
created_date: '2026-07-13 10:37'
updated_date: '2026-07-13 11:33'
labels:
  - Phase2
  - test
dependencies: []
priority: low
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #69（TASK-11）の codex レビュー指摘からの移送（いずれも本 PR 起因ではなく Phase1 共有コード由来 or テスト拡充のため非ブロッカー判断）。(1) IOProc 内の変換・配列確保・Task hop を ring buffer + 非RT worker へ分離（Phase1 マイク経路 installTap→convert→Task と共通のアーキ変更）。(2) AudioSampleConversion.convertToBuffer の frameCapacity ceil 化・AVAudioConverter status 検証（main から verbatim 移設の既存コード。converter のステートフル再利用でドリフトは有界のため実効は低い）。(3) IOContext.process の AudioBufferList→AVAudioPCMBuffer ブリッジの単体テスト。(4) teardown OSStatus の診断ログ。(5) 世代ガードテストの順序保証・timeout。(6) MockSystemAudioTap.setError が未使用（systemAudioCaptureFailed 変換未検証）。実機検証チェックリスト（TCC prompt・実音声・出力デバイス切替）と対で消化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 IOProc 内で RT 予算を超えうる処理（変換・確保・hop）が非RTワーカーへ分離されている
- [ ] #2 変換の status/frameCapacity が検証されテストがある
- [ ] #3 IO ブリッジ経路の単体テストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/101

PR #89 レビューからの追加項目: (a) レベルメーター系統対応テストが mic/system を swap しても通る（rmsLevel(micSamples)/rmsLevel(systemSamples) との突き合わせで固定）。(b) normalize(x)==normalize(x) の恒真テストを削除 or 実効化。(c) WaveformView.currentLevel の dead state と LevelMeterView の dead code 整理。
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
