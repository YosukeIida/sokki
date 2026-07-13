---
id: TASK-23
title: 翻訳APIキーをKeychainで管理
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-12 23:58'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-20
references:
  - 'https://github.com/YosukeIida/sokki/issues/42'
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
translationApiKeyをAppSettings平文からKeychainへ移行する。参照: Recap KeychainService。GitHub Issue #42 (P25-7) 対応。P25-4（翻訳ON/OFFトグル + プロバイダ/言語選択）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 translationApiKeyがAppSettings平文ではなくKeychainに保存されること
- [ ] #2 既存の平文保存値からの移行パスがあること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:58
---
実装完了・PR #95 マージ可能判定（sonnet・Fable レビュー・マージ順 #70→#93→#95）。KeychainService（service/account 分離・実 Keychain テスト）+ SettingsView のキー入力 UI。平文フィールドは履歴上存在せず移行パス不要と判断。統合メモ: #79 マージ後に APIKeyProviding 適合宣言 + DeepL 注入。マージ後: Done 化 + Issue #42 クローズ。
---
<!-- COMMENTS:END -->
