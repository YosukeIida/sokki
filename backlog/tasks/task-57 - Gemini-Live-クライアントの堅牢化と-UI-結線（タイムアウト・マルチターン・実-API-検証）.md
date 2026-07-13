---
id: TASK-57
title: Gemini Live クライアントの堅牢化と UI 結線（タイムアウト・マルチターン・実 API 検証）
status: To Do
assignee: []
created_date: '2026-07-13 16:33'
updated_date: '2026-07-13 16:33'
labels:
  - Phase2.5
dependencies: []
priority: low
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #86（TASK-21）の codex レビューからの移送（translateAudioStream は現状 UI から未到達の実験的コードのため deferred）。(1) prepare() の setup 応答待ちにタイムアウト/キャンセルハンドラがない（無応答サーバで無期限ハング。Coordinator の世代無効化セマンティクスと一体設計が必要）。(2) 単一ターン構造: 既定 VAD では turnComplete がストリーム途中で発火しうるため、長時間録音では最初のターンしか取得できない — 継続音声/UI 結線の再設計と同時に対応。(3) turnComplete 後に最終テキストが到着する順序エッジケース（公式ドキュメントでは順序保証なし。実 API でしか検証不能）。(4) docs の命名/エンドポイント drift（roadmap.md の GeminiLiveProvider vs 実装 GeminiLiveTranslateClient・v1beta/v1alpha）。(5) 既存の async 警告2件（PR 以前から存在）。BYO キーでの実 API 検証とあわせて実施。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 setup 応答待ちにタイムアウトがある
- [ ] #2 長時間録音で複数ターンの翻訳が取得できる
- [ ] #3 実 API での翻訳成立を確認済み
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/110
<!-- SECTION:NOTES:END -->
