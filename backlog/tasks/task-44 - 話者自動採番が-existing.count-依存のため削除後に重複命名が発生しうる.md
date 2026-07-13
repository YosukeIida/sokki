---
id: TASK-44
title: 話者自動採番が existing.count 依存のため削除後に重複命名が発生しうる
status: To Do
assignee: []
created_date: '2026-07-13 08:50'
updated_date: '2026-07-13 13:42'
labels:
  - Phase3
  - bug
dependencies: []
priority: high
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SpeakerProfileStore.findOrCreate の自動採番が既存プロファイル数（existing.count）をそのまま index に使うため、プロファイル削除・rename のライフサイクルをまたぐと命名が衝突する（例: 話者A/B/C の B を削除 → 次の新規話者が count=2 で再び「話者C」になり既存 C と重複）。main 由来の既存欠陥で TASK-38（PR #67）のスコープ外のため切り出し。PR #67 の codex レビュー [MAJOR] 指摘からの移送。SpeakerProfileView の削除 UI（TASK-30 / PR #83）マージ後に実害が顕在化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 採番が削除・rename 後も衝突しない方式（例: 使用中 displayName の集合を避ける、最大 index+1、または連番の永続カウンタ）になっている
- [ ] #2 削除→新規作成の衝突シナリオを再現する回帰テストが追加されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/96
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
