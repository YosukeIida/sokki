---
id: TASK-47
title: SegmentListView の 0.25 秒毎 sortedSegments 再ソートを解消
status: To Do
assignee: []
created_date: '2026-07-13 10:09'
updated_date: '2026-07-13 10:09'
labels:
  - Phase4
dependencies: []
priority: low
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #75/#99（TASK-33）の codex レビュー [MINOR] 指摘からの移送。再生位置の 0.25 秒間隔更新のたびに SessionModel.sortedSegments（computed property で毎回 sorted 実行）が再評価され、セグメント数に比例した無駄な再ソート・再変換が発生する。対応案: ソート済み配列のキャッシュ、または再生位置更新と一覧描画の依存分離。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 再生中の定期更新でセグメント配列の再ソートが発生しない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/100
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
