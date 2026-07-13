---
id: TASK-38
title: 話者自動命名をロケール追従 SpeakerLabel に統一
status: In Progress
assignee: []
created_date: '2026-07-11 18:39'
updated_date: '2026-07-12 21:39'
labels:
  - Phase3
milestone: m-3
dependencies: []
references:
  - Sources/SokkiKit/SpeakerProfile/SpeakerProfileStore.swift
  - 'https://github.com/YosukeIida/sokki/issues/61'
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SpeakerProfileStore.swift:70 の自動命名が「話者 1」「話者 2」形式（カウント+1・日本語固定）になっており、確定仕様のロケール追従話者ラベル（ja=話者A / en=Speaker A、TASK-9.2 で実装した SpeakerLabel.displayName）と乖離している。プロファイル自動作成時の命名を SpeakerLabel 経由に統一する。TASK-9.3 のモック作成時に検出された仕様乖離。話者プロファイルが実際に作られるのは Phase3（diarization 稼働後）のため Phase3 に配置。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SpeakerProfileStore の自動命名が SpeakerLabel.displayName（ロケール追従）を使うこと
- [ ] #2 既存テストが新命名規則で更新されていること
<!-- AC:END -->

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
created: 2026-07-12 21:39
---
実装完了・PR #67 作成済み（sonnet 実装・Fable レビュー済み・マージはユーザー承認待ち）。swift test 56件全て成功。マージ後に Done 化と Issue #61 クローズを行うこと。
---
<!-- COMMENTS:END -->
