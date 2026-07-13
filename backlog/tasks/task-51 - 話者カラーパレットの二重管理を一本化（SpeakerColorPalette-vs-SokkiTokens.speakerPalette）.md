---
id: TASK-51
title: 話者カラーパレットの二重管理を一本化（SpeakerColorPalette vs SokkiTokens.speakerPalette）
status: To Do
assignee: []
created_date: '2026-07-13 12:40'
updated_date: '2026-07-13 12:41'
labels:
  - Phase3
  - design
dependencies: []
priority: low
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #88（TASK-29）の codex レビュー [MAJOR] 指摘からの移送（Phase1 由来の既存構造で #88 の変更範囲外）。永続化される SpeakerProfileModel.colorHex の割り当て元 SpeakerColorPalette（8色: #3B82F6 等）と DesignSystem の SokkiTokens.speakerPalette（3色: #4c7fc0 等）が別管理。アプリ内は colorHex 参照で自己整合しており実害は DesignSystemGallery プレビューとの見た目乖離に留まるが、デザイントークン適用（TASK-43）の際に正規パレットへ一本化する。あわせて (a) 恒真テスト sameHexSameColor の実効化、(b) Snapshot fixture に複数 SpeakerProfileModel を割り当てて話者色分岐を検証、(c) SegmentListView の Color.secondary.opacity(0.3) のトークン化。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 話者色の割り当てとデザイントークンのパレットが単一ソースになっている
- [ ] #2 複数話者色を描画する Snapshot/テストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/104
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
