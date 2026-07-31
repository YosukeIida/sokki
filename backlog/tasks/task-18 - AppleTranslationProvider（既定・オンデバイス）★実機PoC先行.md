---
id: TASK-18
title: AppleTranslationProvider（既定・オンデバイス）★実機PoC先行
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-13 16:50'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-17
references:
  - 'https://github.com/YosukeIida/sokki/issues/37'
documentation:
  - docs/translation-architecture.md
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
macOS 15 Translation Frameworkで確定セグメントを翻訳する。.translationTask制約に対応した供給経路を実装する。19言語対応、モデルダウンロードプロンプト対応。実機PoCを先行させる位置づけ。GitHub Issue #37 (P25-2) 対応。P25-1（TranslationProvider protocol）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 macOS 15 Translation Frameworkで確定セグメントを翻訳できること
- [ ] #2 .translationTask制約に対応した供給経路が実装されていること
- [ ] #3 モデル未ダウンロード時にダウンロードプロンプトが出ること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PR #70 レビューからの必須申し送り（real provider 結線時に対応）: (1) 単一 appleProvider インスタンスの再利用 race — 旧 teardown の suspension 中に新 reconcile が同一 actor を再 prepare すると旧 teardown 復帰が新セッションを閉じうる（real provider の teardown が内部 suspension を持つ場合のみ顕在化）。lease 化 or per-provider in-flight-close 追跡が必要。(2) overlapping teardown の再入契約を protocol に明記 + テスト。(3) PR #94 レビュー指摘: TranslationCoordinator.teardown 系で isCloudActive=false を provider.teardown() 完了前にセットする過渡ウィンドウ（現状は placeholder のみで休眠）— インジケーター表示の正確性のため完了後更新へ。※いずれも inputCont が prepare 中 nil のため「ユーザー音声のクラウド送信ゼロ」保証自体は破れない（#70 ワーカー検証済み）。

PR #80 レビュー完了（2026-07-14・マージは実機 PoC 待ちのまま）: BLOCKER 2件 + MAJOR 3件 + 再レビュー新規1件（drain 終了後の continuation リーク）を修正済み（〜1101204 push 済み）。**重要: 実アプリに TranslationHostView が未マウント（DI 結線は §15(c) Coordinator タスクに委譲済み）のため、結線完了までは prepare() が必ず awaitReady timeout で fail-closed になり実機 PoC 自体が実行不能**。PoC 実行の前提 = Coordinator 結線（統合タスク）を先に実施すること。PoC 確認項目: (1) DI 結線後の .translationTask 常駐 drain 成立、(2) 言語ペア変更・同一ペア再設定での Configuration.invalidate() 実挙動、(3) 0pt 不可視ホストからの DL 同意 UI、(4) View/ウィンドウ close 時の action task cancel と drainEnded クリーンアップ、(5) awaitReady 既定 timeout 10 秒の妥当性。TranslationSession.Configuration は Sendable 非準拠（swiftinterface 確認済み）のため境界越えは UInt64 世代スナップショットのみ。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:15
---
実装完了・PR #80（opus 実装・codex クロスレビュー + 修正・マージ順 #70→#80）。他の PR と異なり **マージは実機 PoC 成功が前提条件**: (1) .translationTask closure 常駐 drain の成立 (2) 0pt ホストからのモデル DL 同意 UI 表示（Fallback 案は PR 本文）(3) ja↔en 実翻訳。Bridge は世代 ID + レジストリ + once-guard の状態機械、95テスト。PoC 成功後: マージ + Done 化 + Issue #37 クローズ + TASK-19 解放。
---
<!-- COMMENTS:END -->
