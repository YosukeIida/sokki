---
id: TASK-36
title: プライバシーモード切替UI + ローカル/APIインジケーター
status: Done
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-13 17:05'
labels:
  - Phase5
milestone: m-5
dependencies:
  - TASK-20
references:
  - 'https://github.com/YosukeIida/sokki/issues/55'
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既定ONとし、状態を録音画面に明示する。isOnDevice==falseのプロバイダの抑止と連動させる。GitHub Issue #55 (P5-1) 対応。P25-4（翻訳ON/OFFトグル + プロバイダ/言語選択）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 プライバシーモードが既定ONであること
- [ ] #2 録音画面にローカル/APIの状態が明示されること
- [ ] #3 isOnDevice==falseのプロバイダの抑止と連動すること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: 録音画面にローカル/API 処理インジケーター（ProcessingModeIndicator 純粋関数 + バッジ表示、録音中のみ・isCloudActive 連動）を追加。codex レビューの MAJOR（teardown 時の isCloudActive 更新順序の過渡ウィンドウ）は #70 由来の休眠バグとして TASK-18 申し送りに記録済み。PR #94 マージ済み（2026-07-14）。実機検証: UI 目視。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:56
---
実装完了・PR #94 マージ可能判定（sonnet・Fable レビュー・マージ順 #70→#93→#94）。ProcessingModeIndicator 純粋関数 + isCloudActive 連動バッジ、91テスト。AC1/AC3 は TASK-17/20 で充足済みを確認。マージ後: Done 化 + Issue #55 クローズ。
---
<!-- COMMENTS:END -->
