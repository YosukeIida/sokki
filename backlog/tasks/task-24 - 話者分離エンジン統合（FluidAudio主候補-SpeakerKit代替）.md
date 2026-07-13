---
id: TASK-24
title: 話者分離エンジン統合（FluidAudio主候補 / SpeakerKit代替）
status: Done
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-13 13:04'
labels:
  - Phase3
milestone: m-3
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/43'
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DiarizationEngine準拠のFluidAudioEngineを追加し、diarizeが実データのDiarizationSegmentを返すようにする。SpeakerKitとprotocolレベルで交換可能な設計を維持する。GitHub Issue #43 (P3-1) 対応。依存なし（Phase3の基盤）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DiarizationEngine準拠のFluidAudioEngineが追加され、diarizeが実データのDiarizationSegmentを返すこと
- [ ] #2 SpeakerKitとprotocolレベルで交換可能であること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: FluidAudio（0.15.5・OfflineDiarizerManager）を既定の話者分離エンジンとして統合。DiarizationEngine protocol 抽象で SpeakerKitEngine と交換可能（D-11 準拠・spec.md 更新済み）。AppDependencyContainer は any DiarizationEngine 化。codex レビュー: 指摘4件は全てエンジン未配線（配線は #77）のため非ブロッカー、TASK-55/#108（hardening）へ集約移送。実 API 契約との一致・entitlements 保持を検証済み。main 統合で #82 の engine factory と併存解消。PR #68 マージ済み（2026-07-13）。実機検証: FluidAudio モデル初回 DL・実音声 diarize。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:08
---
実装完了・PR #68 マージ可能判定（codex gpt-5.6-sol 実装・sonnet 仕上げ・code-reviewer APPROVE・マージはユーザー承認待ち）。FluidAudio 0.15.5 OfflineDiarizerManager 既定化、256次元 WeSpeaker embedding を L2 正規化して返却、SpeakerKitEngine は代替として残置。swift test 59件パス。実機検証（ユーザー）: 実音声 diarize + モデル初回 DL。マージ後: Done 化 + Issue #43 クローズ + TASK-25/26 解放。
---
<!-- COMMENTS:END -->
