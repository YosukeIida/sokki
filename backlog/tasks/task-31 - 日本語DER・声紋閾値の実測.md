---
id: TASK-31
title: 日本語DER・声紋閾値の実測
status: In Progress
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 23:19'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:19
---
ハーネス実装完了・PR #90 マージ可能判定（opus・Fable レビュー・マージ順 #87系→#90）。DER 計算器（NIST 定義・collar・最適マッピング）+ RTTM/TSV パーサ + 環境変数ゲート付き計測テスト + docs/diarization-benchmark.md、96テスト。実測（ユーザー）: 日本語音声で DER 取得し requirements.md の Open Question をクローズ。マージ後: Done 化 + Issue #50 クローズ（実測完了時）。
---
<!-- COMMENTS:END -->
