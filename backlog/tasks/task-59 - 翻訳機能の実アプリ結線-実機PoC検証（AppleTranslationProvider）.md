---
id: TASK-59
title: 翻訳機能の実アプリ結線 + 実機PoC検証（AppleTranslationProvider）
status: To Do
assignee: []
created_date: '2026-07-31 16:56'
updated_date: '2026-07-31 16:58'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-18
references:
  - 'https://github.com/YosukeIida/sokki/issues/37'
  - 'https://github.com/YosukeIida/sokki/issues/115'
priority: high
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-18（PR #80・マージ済み）は実機PoC成功をマージ前提条件としていたが、ユーザー判断により「PoC検証は別タスクに切り出し、実装はマージ」の方針に変更（2026-08-01）。本タスクはその切り出された実機検証スコープを引き継ぐ。

現状: main には AppleTranslationProvider / TranslationSessionBridge が実装済みだが、TranslationHostView は実アプリにまだDI結線されていない（TranslationCoordinator.appleProvider はプレースホルダのまま）。結線しない限り prepare() は必ず awaitReady timeout で fail-closed になり、以下のPoC自体が実行不可能。

作業: (1) TranslationCoordinator の appleProvider プレースホルダを実 AppleTranslationProvider に差し替え、(2) TranslationHostView を実アプリ（RecordingView 等）にDI結線する。結線後、実機で以下を確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TranslationHostView が実アプリにマウントされ、Coordinator から実際の AppleTranslationProvider が使われること
- [ ] #2 .translationTask 常駐 drain が実機で成立し、デッドロック・continuation リークが発生しないこと
- [ ] #3 言語ペア変更・同一ペア再設定時に Configuration.invalidate() が実挙動として機能すること
- [ ] #4 0pt 不可視ホストからモデルダウンロード同意UIが表示されること（表示されない場合はフォールバックUIを実装する）
- [ ] #5 ja↔en の実翻訳が正しく動作すること
- [ ] #6 awaitReady の既定タイムアウト（10秒）が実運用で妥当か確認する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
