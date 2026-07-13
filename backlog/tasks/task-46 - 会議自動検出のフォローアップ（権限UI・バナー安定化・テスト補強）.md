---
id: TASK-46
title: 会議自動検出のフォローアップ（権限UI・バナー安定化・テスト補強）
status: To Do
assignee: []
created_date: '2026-07-13 09:33'
updated_date: '2026-07-13 09:34'
labels:
  - Phase2
dependencies: []
priority: low
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #74（TASK-15）の codex レビュー指摘からの移送。(1) [MAJOR#4] SCShareableContent.current は画面収録 TCC の対象で、権限拒否時に検出が無言で動かない — 権限状態の UI 表示（SettingsView に権限確認/誘導）を追加する。実 TCC 挙動は doc-1 実機検証チェックリストで確認。(2) [MINOR#7] 一時的な検出漏れ1回でバナーが消失・再出現する — 表示側にもヒステリシス（missesBeforeReset 相当の猶予）を付ける。(3) [MINOR#8 残] RecordingView 層のライフサイクル（onAppear/onDisappear × 録音状態）の統合テスト追加、in-flight レーステストの 50ms 固定 sleep の厳密化。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 画面収録権限が未許可のとき、会議検出設定 UI で権限状態が分かり許可への導線がある
- [ ] #2 一時的な検出漏れ1回ではバナーが消えない（表示ヒステリシス）
- [ ] #3 RecordingView 層のライフサイクル統合テストが追加されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/98
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
