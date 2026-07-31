---
id: TASK-19
title: 翻訳字幕UI（2レーン + フローティング）
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-13 16:34'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-18
  - TASK-14
references:
  - 'https://github.com/YosukeIida/sokki/issues/38'
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
録音中に原文/訳文の2レーン表示を行う。会議横のフローティングオーバーレイ（NSPanel, sharingType=.noneで画面共有に映り込まない）を実装する。GitHub Issue #38 (P25-3) 対応。P25-2（AppleTranslationProvider）およびP2-4（リアルタイムストリーミング文字起こし）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 録音中に原文/訳文の2レーン表示が動作すること
- [ ] #2 NSPanelでsharingType=.noneのフローティングオーバーレイが画面共有に映り込まないこと
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PR #92 レビュー完了（マージは base #80 の実機 PoC 待ち）。BLOCKER: sharingType=.none は macOS 15+ の ScreenCaptureKit ベースの画面共有・収録では無視される（Apple が legacy 扱い・既知の回避策なし）— 非映り込みは機能保証できずクラス doc に制約明記済み。実機検証で Zoom/QuickTime の挙動を確認し、映り込む場合は共有中自動非表示のフォールバック UX を検討。MAJOR 4件は修正済み（録音停止時の close 結線・.closable 除外・trim 順序統一・maxLines didSet ガード）。統合申し送り: pushConfirmed 配線時に SubtitleFeed.reset() のセッション境界配線も忘れないこと。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:33
---
実装完了・PR #92 マージ可能判定（opus・Fable レビュー・マージ順 #70→#80（PoC 前提）→#92）。SubtitleFeed（確定のみ push・訳文は描画時 id 突き合わせ）+ 2レーンビュー + FloatingSubtitlePanel（sharingType=.none 属性テスト済み）、108テスト。統合メモ: トグル表示条件は TASK-20 の translationEnabled に差し替え、LiveTranscriptView の2レーン化は上流マージ後。実機検証（ユーザー）: 画面共有への非映り込み・最前面・クリック透過。マージ後: Done 化 + Issue #38 クローズ。
---
<!-- COMMENTS:END -->
