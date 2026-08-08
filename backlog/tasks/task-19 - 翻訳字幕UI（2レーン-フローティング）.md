---
id: TASK-19
title: 翻訳字幕UI（2レーン + フローティング）
status: Done
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-31 16:58'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PR #92 マージ済み（マージコミット 3473bd3）。SubtitleFeed + 2レーンビュー + FloatingSubtitlePanel（NSPanel, sharingType=.none）を実装。codex-pr-reviewでMAJOR4件修正済み、112テスト全PASS。

マージ時にRecordingView.swiftで実際のコンフリクトが発生（#80のTranslationCoordinator reconcile/会議検出ロジックと#92のフローティング字幕トグルが同一View修飾子チェーンに独立追加されていたため）。両機能を完全に保持する形で手動解消し、build成功・387/388テストPASSを確認（残り1件はrecordingWithText snapshotの画像差分で、新規UI要素追加による既知の想定内差分。実機再記録は既存の統合タスクで対応予定）。

方針転換（2026-08-01・ユーザー判断）: 当初マージ前提条件としていた実機PoC（画面共有非映り込み確認等）は、コード実装自体は問題ないため、実機PoC検証をTASK-60に切り出してマージを実行した。PR #92レビューで`sharingType=.none`がmacOS 15+のScreenCaptureKit経由では無視される既知の制約が判明しており、フォールバックUXの検討もTASK-60で扱う。

Issue #38 はこのタスクの実装スコープ完了としてクローズ。実機検証・フォールバックUXの残課題はTASK-60（Issue #116）で追跡する。
<!-- SECTION:FINAL_SUMMARY:END -->
