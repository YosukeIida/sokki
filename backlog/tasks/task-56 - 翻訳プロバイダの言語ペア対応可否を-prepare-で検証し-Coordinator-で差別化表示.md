---
id: TASK-56
title: 翻訳プロバイダの言語ペア対応可否を prepare() で検証し Coordinator で差別化表示
status: To Do
assignee: []
created_date: '2026-07-13 16:28'
updated_date: '2026-07-13 16:28'
labels:
  - Phase2.5
dependencies: []
priority: medium
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #79（TASK-22）の codex レビュー [MAJOR] からの移送（codex とワーカーで意見対立 → 司令塔がフォローアップ判断）。(1) DeepLTranslationProvider.prepare() が言語ペア対応可否を検証せず、非対応ペアでも activate が成功して「クラウド送信中」バナーが出た後、最初のセグメント送信で初めて失敗する（一時的 false-positive）。静的 allow-list は陳腐化リスクがあるため DeepL の /v2/languages エンドポイントでの動的取得を検討。(2) TranslationCoordinator.activate() は .modelNotDownloaded 以外の失敗を一律 .failed → 汎用エラーバナーにしており、languagePairUnsupported を差別化する分岐がない — BYO プロバイダ全体に共通する設計論点のため「Coordinator がどう見せるか」まで含めて設計する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 非対応言語ペアで prepare() が languagePairUnsupported を返す（DeepL）
- [ ] #2 Coordinator が言語ペア非対応を汎用エラーと区別してユーザーに提示する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/109
<!-- SECTION:NOTES:END -->
