---
id: TASK-11
title: システム音声キャプチャ（Core Audio Taps / ProcessTap）
status: Done
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-13 10:39'
labels:
  - Phase2
milestone: m-1
dependencies:
  - TASK-10
references:
  - 'https://github.com/YosukeIida/sokki/issues/30'
documentation:
  - docs/recap-codebase-analysis.md
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AudioCaptureManagerにProcessTapを内包し、systemStream / systemLevelStreamを配線する。startCapture(.systemOnly)のthrowを解除する。参照: docs/recap-codebase-analysis.md §0+本文（WhisperKit/entitlementの訂正に注意）。GitHub Issue #30 (P2-1) 対応。P2-0（配布方針決定）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AudioCaptureManagerにProcessTapを内包し、systemStream / systemLevelStreamを配線する
- [ ] #2 startCapture(.systemOnly)がthrowしなくなり、実際にシステム音声がキャプチャできること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
【TASK-10 決定を踏まえた注記・2026-07-13】無署名/ad-hoc 署名ビルドでは Core Audio Taps の TCC prompt（NSAudioCaptureUsageDescription）が発火しない可能性が高いという実体験報告が複数ある（Apple公式の明文規定は未確認）。実装自体は無署名でも進められるが、実機での動作確認は Developer ID 署名 or 安定した signing identity が無いと成立しない可能性がある。着手時は早い段階で無署名ビルドでの TCC prompt 発火有無を実機確認し、発火しない場合は Developer ID 取得のタイミングをこのタスクの前提条件として扱うこと。

finalSummary: Core Audio Taps（CATapDescription + AudioHardwareCreateProcessTap + aggregate device）によるシステム音声キャプチャを実装（設計判断 D-9改訂/D-10 準拠、SCStream は代替）。SystemAudioTap 新規 + AudioCaptureManager 統合 + AudioSampleConversion 共通化。captureGeneration による停止後 Task 排除。codex レビュー（effort=high）指摘は全件が Phase1 共有コード由来 or テスト拡充のため修正なしで APPROVE、TASK-48/#101（hardening）へ移送。xcodegen 後の entitlements 3権限保持を検証済み。PR #69 マージ済み（2026-07-13）。実機検証: 無署名ビルドでの TCC prompt 発火確認が最重要（doc-1）。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:02
---
実装完了・PR #69 マージ可能判定（opus 実装・codex クロスレビュー2周 + Fable レビュー済み・マージはユーザー承認待ち）。swift test 65件パス。主な成果: SystemAudioTap + CoreAudioTapSystem 注入層、世代トークンで旧セッション音声混入を防止（mic/system 両経路）。※ systemOnly の録音ファイル保存は TASK-12 に委譲。実機検証（ユーザー）: 無署名ビルドでの TCC prompt 発火確認（PR #71 の検証で発火しない可能性高い）・実システム音声の文字起こし・TCC 拒否時挙動・出力デバイス切替。マージ後: Done 化 + Issue #30 クローズ + Wave2（TASK-12/13/14）解放。
---
<!-- COMMENTS:END -->
