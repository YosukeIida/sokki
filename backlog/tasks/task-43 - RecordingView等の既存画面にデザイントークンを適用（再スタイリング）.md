---
id: TASK-43
title: RecordingView等の既存画面にデザイントークンを適用（再スタイリング）
status: To Do
assignee: []
created_date: '2026-07-12 20:23'
updated_date: '2026-07-12 20:23'
labels:
  - Phase1
  - design
milestone: m-0
dependencies:
  - TASK-9.2
references:
  - 'https://github.com/YosukeIida/sokki/issues/66'
priority: medium
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-9.2 でデザイントークン基盤（`SokkiTokens` / `DesignSystemComponents`）を構築したが、実装済みの画面（`RecordingView` / `SessionListView` / `SessionRowView` / `SegmentListView` / `SessionDetailView`）はどれもトークンを一切使わず「素の SwiftUI」のままになっている（ハードコードされた `Color(nsColor: .controlBackgroundColor)` 等）。

`docs/design/recording-view-v3.html` と `DESIGN.md` で確定した内容を実装に反映する。特に、録音ボタンは現状 SF Symbol の 44pt グリフのみで、モックが定義する 56px 丸背景（`record-button-idle` / `record-button-recording`）が描画されていない。

Console（ダーク）/ Manuscript（ライト）両テーマで、DESIGN.md の Components 定義（titlebar, sidebar, capture-mode-segment, status-chip, toggle-switch, waveform-bar, transcript-line, record-button, speaker-color-bar 等）とコードの実装を一致させる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 RecordingView / SessionListView / SessionRowView / SegmentListView / SessionDetailView が @Environment(\.sokkiTokens) 経由でトークンを参照し、ハードコードされた色指定を置き換える
- [ ] #2 録音ボタンを DESIGN.md の record-button-idle / record-button-recording 定義（56px 丸形背景 + 22px グリフ、recording 時は rec 色 50% 透過のリング）に合わせて実装する
- [ ] #3 Console・Manuscript 両テーマで RenderPreview 等で目視確認する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
