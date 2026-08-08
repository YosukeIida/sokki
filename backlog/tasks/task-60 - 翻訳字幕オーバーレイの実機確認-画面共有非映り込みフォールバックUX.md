---
id: TASK-60
title: 翻訳字幕オーバーレイの実機確認 + 画面共有非映り込みフォールバックUX
status: To Do
assignee: []
created_date: '2026-07-31 16:57'
updated_date: '2026-07-31 16:58'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-19
  - TASK-59
references:
  - 'https://github.com/YosukeIida/sokki/issues/38'
  - 'https://github.com/YosukeIida/sokki/issues/116'
priority: medium
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-19（PR #92・マージ済み）は実機PoC成功をマージ前提条件としていたが、ユーザー判断により「PoC検証は別タスクに切り出し、実装はマージ」の方針に変更（2026-08-01）。本タスクはその切り出された実機検証スコープを引き継ぐ。

PR #92 レビューで判明した既知の制約: `sharingType = .none` は macOS 15+ の ScreenCaptureKit ベースの画面共有・収録では無視される（Apple が legacy 扱い・既知の回避策なし）。このため「画面共有に映り込まない」という機能保証はコードでは実現できず、実機での挙動確認とフォールバックUXの検討が必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Zoom会議中の画面共有でフローティング字幕パネルが映り込むかどうかを実機確認する
- [ ] #2 QuickTime画面収録でも同様に確認する
- [ ] #3 映り込む場合、共有検出時に自動非表示にするフォールバック挙動を実装する
- [ ] #4 最前面表示・クリック透過が実機で機能することを確認する
- [ ] #5 実翻訳（TASK-59完了後）を伴った状態での2レーン表示を確認する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
