---
id: TASK-31
title: 日本語DER・声紋閾値の実測
status: Done
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-13 13:53'
labels:
  - Phase3
  - test
milestone: m-3
dependencies:
  - TASK-26
references:
  - 'https://github.com/YosukeIida/sokki/issues/50'
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
日本語音声でDER（Diarization Error Rate）と声紋閾値0.82の妥当性を計測する。参考: Sortformer 12.7% / Pyannote 28.8%。Open Questionを閉じる。GitHub Issue #50 (P3-8) 対応。P3-3（WhisperKitセグメントとdiarizationのマージ）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 日本語音声でDERを計測し、Sortformer/Pyannoteの実績値と比較する
- [ ] #2 声紋閾値 0.82 の妥当性を検証し、requirements.mdのOpen Questionを閉じる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: DER 計測ハーネス（DERCalculator + RTTMParser）と実測手順書 docs/diarization-benchmark.md を追加。codex レビューで実バグ修正（同一話者重複区間の二重計上による負の confusion → Set 一意化）+ RTTM 不正入力のエラー化（NaN/Inf/dur<=0）+ 閾値材料を DER 最適マッピングでリファレンス話者へ読み替え。貪欲マッピング（>8話者非最適）と分母0時 DER=0 は文書化済み設計判断として維持。PR #90 マージ済み（2026-07-13）。実機検証: 日本語実データでの DER 実測（docs 手順・doc-1）。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:19
---
ハーネス実装完了・PR #90 マージ可能判定（opus・Fable レビュー・マージ順 #87系→#90）。DER 計算器（NIST 定義・collar・最適マッピング）+ RTTM/TSV パーサ + 環境変数ゲート付き計測テスト + docs/diarization-benchmark.md、96テスト。実測（ユーザー）: 日本語音声で DER 取得し requirements.md の Open Question をクローズ。マージ後: Done 化 + Issue #50 クローズ（実測完了時）。
---
<!-- COMMENTS:END -->
