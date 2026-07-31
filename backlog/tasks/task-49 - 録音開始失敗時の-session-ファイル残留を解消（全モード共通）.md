---
id: TASK-49
title: 録音開始失敗時の session/ファイル残留を解消（全モード共通）
status: To Do
assignee: []
created_date: '2026-07-13 10:39'
updated_date: '2026-07-13 10:39'
labels:
  - Phase2
  - bug
dependencies: []
priority: medium
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #81（TASK-12）の codex レビュー [MAJOR] 指摘からの移送。TranscriptionPipeline.start は session 作成後の start 失敗に do/catch がなく、AudioFileWriter が init 時にファイルを生成するため、キャプチャ起動失敗時に 0 秒 session と空ファイル（primary / _system）が残留する。micOnly/systemOnly でも起きる既存の全モード共通ギャップ（#81 の回帰ではない）。対応には pipeline 層で PersistentIdentifier ベースの session 削除 API が必要（現 deleteSession は UUID 引数）。capture manager 内でファイルだけ消す部分対応は「実体を失った session が残る」ため不採用。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 キャプチャ起動失敗時に作成済み session と空音声ファイルがロールバック削除される
- [ ] #2 micOnly/systemOnly/both の各失敗経路の回帰テストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/102
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
