---
id: TASK-40
title: WhisperKit モデルダウンロードの進捗（%）表示
status: Done
assignee: []
created_date: '2026-07-12 12:20'
labels:
  - Phase1
milestone: m-0
dependencies: []
references:
  - 'commit:90eb929'
modified_files:
  - Sources/SokkiKit/Transcription/TranscriptionEngine.swift
  - Sources/SokkiKit/Transcription/WhisperKitEngine.swift
  - Sources/SokkiKit/Transcription/TranscriptionPipeline.swift
  - Sources/SokkiKit/UI/RecordingView/RecordingView.swift
  - Sources/SokkiKit/Mocks/PreviewMocks.swift
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
初回起動時のWhisperKitモデルダウンロードが「ロード中…」の固定メッセージのみで進捗が見えず、フリーズと区別がつかないというユーザーフィードバックを受けて実装。TranscriptionEngine.prepare(onProgress:) を追加し、WhisperKitEngine は WhisperKit.download(progressCallback:) でダウンロードとメモリロードを明示的に分離、実際のバイト単位の進捗を取得できるようにした。TranscriptionPipeline に downloadProgress を追加しRecordingViewのローディング画面にプログレスバー+パーセンテージ表示を配線。
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
既存の引数なし prepare() は後方互換のデフォルト実装として維持しつつ、prepare(onProgress:) でダウンロード中/メモリロード中のフェーズを通知できるようにした。RenderPreviewで42%表示を実機確認、テスト4件追加、既存スナップショット1件を意図的な変更として再記録（swift test 全件pass）。
<!-- SECTION:FINAL_SUMMARY:END -->
