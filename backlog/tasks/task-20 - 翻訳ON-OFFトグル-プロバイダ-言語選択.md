---
id: TASK-20
title: 翻訳ON/OFFトグル + プロバイダ/言語選択
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-12 23:46'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-17
references:
  - 'https://github.com/YosukeIida/sokki/issues/39'
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SettingsViewと録音画面トグルを実装する。OFF時はクラウド送信ゼロにする。プライバシーモード時はisOnDevice==falseのプロバイダを抑止する。GitHub Issue #39 (P25-4) 対応。P25-1（TranslationProvider protocol）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SettingsViewと録音画面に翻訳トグルがあること
- [ ] #2 OFF時はクラウド送信がゼロであること
- [ ] #3 プライバシーモード時はisOnDevice==falseのプロバイダが抑止されること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:46
---
実装完了・PR #93 マージ可能判定（sonnet・Fable レビュー・マージ順 #70→#93）。翻訳設定 UI + TranslationCoordinator の DI 結線（プレースホルダ方式・差し替え点明記）。副産物: Settings シーンの DI 欠落と ModelContext 競合の発見・修正、88テスト。マージ後: Done 化 + Issue #39 クローズ + TASK-23/36 解放（着手済み）。
---
<!-- COMMENTS:END -->
