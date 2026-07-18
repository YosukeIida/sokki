---
id: TASK-44
title: 話者自動採番が existing.count 依存のため削除後に重複命名が発生しうる
status: In Progress
assignee: []
created_date: '2026-07-13 08:50'
updated_date: '2026-07-18 20:30'
labels:
  - Phase3
  - bug
dependencies: []
modified_files:
  - Sources/SokkiKit/SpeakerProfile/SpeakerProfileStore.swift
  - Tests/sokkiTests/SpeakerProfileStoreTests.swift
priority: high
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SpeakerProfileStore.findOrCreate の自動採番が既存プロファイル数（existing.count）をそのまま index に使うため、プロファイル削除・rename のライフサイクルをまたぐと命名が衝突する（例: 話者A/B/C の B を削除 → 次の新規話者が count=2 で再び「話者C」になり既存 C と重複）。main 由来の既存欠陥で TASK-38（PR #67）のスコープ外のため切り出し。PR #67 の codex レビュー [MAJOR] 指摘からの移送。SpeakerProfileView の削除 UI（TASK-30 / PR #83）マージ後に実害が顕在化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 採番が削除・rename 後も衝突しない方式（例: 使用中 displayName の集合を避ける、最大 index+1、または連番の永続カウンタ）になっている
- [x] #2 削除→新規作成の衝突シナリオを再現する回帰テストが追加されている
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
SpeakerProfileStore.findOrCreate の採番を `existing.count` から「使用中 displayName 集合を避ける最小 index」方式に変更（Sources/SokkiKit/SpeakerProfile/SpeakerProfileStore.swift:114-135）。allProfiles() は未保存 insert も含むため同一 resolveProfiles 内の連続作成も衝突しない。回帰テスト「中間プロファイル削除後の新規話者は空いた名前を埋め、既存名と衝突しない」を追加（Tests/sokkiTests/SpeakerProfileStoreTests.swift）。swift build / swift test（SpeakerProfileStore 系 10 件）PASS。project.yml 変更なしのため DoD#3(xcodegen) は該当なし。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude-code
created: 2026-07-18 20:30
---
PR #113 作成: https://github.com/YosukeIida/sokki/pull/113 — 採番を「使用中 displayName 集合を避ける最小 index」方式に変更し、削除後の命名衝突を解消。回帰テスト1件追加、SpeakerProfileStore 系テスト10件 PASS。レビュー待ち（マージ後に Done + Issue #96 クローズ）。
---
<!-- COMMENTS:END -->
