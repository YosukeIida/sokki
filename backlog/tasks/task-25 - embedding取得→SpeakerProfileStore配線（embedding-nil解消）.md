---
id: TASK-25
title: 'embedding取得→SpeakerProfileStore配線（embedding: nil解消）'
status: Done
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-13 13:31'
labels:
  - Phase3
milestone: m-3
dependencies:
  - TASK-24
references:
  - 'https://github.com/YosukeIida/sokki/issues/44'
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
diarizationが256dim L2正規化embeddingを返し、SpeakerProfileStoreが実働（findOrCreate / EMA更新）するようにする。現状embedding: nilの空回りを解消する。GitHub Issue #44 (P3-2) 対応。P3-1（話者分離エンジン統合）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 diarizationが256dim L2正規化embeddingを返すこと
- [ ] #2 SpeakerProfileStoreがfindOrCreate / EMA更新で実働すること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PR #85 レビューからの統合申し送り（ProcessingCoordinator への diarization 接続時に対応）: (1) [MAJOR] cancelCurrentJob() が captureTask.value の待機をキャンセル伝播しない（handleWillTerminate 経路のみ・確定セグメントは逐次永続化済みのため実害は最終未確定行のみ）。制御可能な capture Task の統合テスト基盤とあわせて解消。(2) [MAJOR] .diarize 拡張点: finalizeTranscription が flush+fallback+録音長保存を一括実行するため、diarize→保存の順にするには .flushTranscription/.diarize/.finalizeSession へのフェーズ分割が必要（統合時の重要設計判断）。(3) persistPendingHypothesisFallback はライブ状態を読むため、fire-and-forget の enqueue を導入する場合は finalize を job コンテキストに固めること。

finalSummary: diarization をパイプラインへ配線し話者プロファイルを実働化（embedding: nil 解消）。AudioFileReader 新規 + stop() 後の runDiarizationIfEnabled → diarizeAndAssign → resolveProfiles（PersistentIdentifier 返却・@Model 境界規約準拠）。codex レビューで MAJOR 4件修正: stop/start 競合（isFinalizing）・bestOverlapSpeaker の合計重なり化・AVAudioConverter 末尾 flush・【新規テストが発見した実バグ】16kHz 直読でも AVAudioFile.read の部分読みで末尾 40ms 欠落 → readAllFrames 化。main 統合で coordinator ジョブ構造（#85）と isFinalizing を重ね、streaming（#76）のキャプチャ済み sessionID 保存とロケール追従命名（#67）へテスト適応。PR #77 マージ済み（2026-07-13）。統合申し送り（.diarize フェーズ分割等）は本タスクコメント参照。実機検証: FluidAudio モデル DL・実音声 diarize。
<!-- SECTION:NOTES:END -->
