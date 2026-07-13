---
id: TASK-55
title: >-
  FluidAudioEngine の hardening（single-flight prepare・embedding 値検証・cancellation
  素通し）
status: To Do
assignee: []
created_date: '2026-07-13 13:01'
updated_date: '2026-07-13 13:01'
labels:
  - Phase3
dependencies: []
priority: low
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #68（TASK-24）の codex レビューからの移送。DiarizationEngine.prepare()/diarize() は #68 時点で未配線（#77 で配線）のため非ブロッカーと判断した hardening 一式: (1) prepare() の single-flight 化（actor は await 間で再入可能。FluidAudio 側の prepareModels は早期 return するが同時 prepare 競合は防げない）+ FluidAudioEngine.swift:10-11 の過大コメント（prevents concurrent access even while suspended）訂正。(2) embedding の有限性/ノルム検証（現状要素数のみ。l2Normalize のゼロガードはあるが NaN/Inf 値検証は永続化配線後に必要）。(3) 包括 catch が CancellationError を diarizationFailed に包む問題（SpeakerKitEngine は素通し・交換時に挙動差）。(4) stateful actor mock による再入・回復（失敗→再 prepare）テスト。(5) numberOfSpeakers を Set(speakerID) で算出している点の実機 diarize での妥当性確認。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 prepare() が single-flight でテストされている
- [ ] #2 CancellationError が素通しされる
- [ ] #3 embedding の有限性検証がある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/108
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
