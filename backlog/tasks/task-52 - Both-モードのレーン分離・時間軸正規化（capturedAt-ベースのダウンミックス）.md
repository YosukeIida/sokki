---
id: TASK-52
title: Both モードのレーン分離・時間軸正規化（capturedAt ベースのダウンミックス）
status: To Do
assignee: []
created_date: '2026-07-13 12:42'
updated_date: '2026-07-13 12:42'
labels:
  - Phase2
  - Phase3
  - bug
dependencies: []
priority: medium
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #81 の到着順インターリーブによる時間軸2倍化（両レーン同時発話でセグメントタイムスタンプが約2倍・レーン間順序も非決定的）の根本解消。PR #87 レビューの診断: 修正は SpeakerAlignment ではなく音声キャプチャ + .both 配線層に閉じる。AudioChunk は既に lane と capturedAt を保持済みのため、到着順連結ではなく capturedAt ベースの実タイムラインで mic/system をダウンミックス（合成）してから文字起こしへ流す方式が最有力。これで transcription と diarization が同一実軸を共有し SpeakerAlignment は無改修で正しく動く。影響範囲: AudioCaptureManager（マージ処理）+ TranscriptionPipeline（.both 実装）+ 同時発話下のタイムライン正当性テスト。規模: M。あわせてモックエンジンの時間軸検証強化（PR #81 レビュー指摘）も行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 両レーン同時発話でもセグメントタイムスタンプが実時間と一致する
- [ ] #2 diarization（実タイムライン）と transcription のタイムスタンプが同一軸で整合する
- [ ] #3 同時発話のタイムライン正当性テストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/105
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
