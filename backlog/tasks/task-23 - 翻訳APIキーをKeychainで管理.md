---
id: TASK-23
title: 翻訳APIキーをKeychainで管理
status: Done
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-13 17:09'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: 翻訳 API キーの Keychain 管理（KeychainService: SecItem add/update/delete + SettingsView の SecureField 入力・マスク表示・保存/削除）を実装。codex レビューで MAJOR 修正: body 評価毎の SecItemCopyMatching 同期実行 → @State キャッシュ化、Keychain 拒否時のエラー差別化（errSecAuthFailed 等 → キーチェーンアクセス App への導線表示）。無署名/ad-hoc 配布での ACL 継続性は実機検証項目（doc-1 追記済み）。APIKeyProviding（#79）との完全一致を確認済み — 適合宣言は統合タスクで1行。PR #95 マージ済み（2026-07-14）。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:58
---
実装完了・PR #95 マージ可能判定（sonnet・Fable レビュー・マージ順 #70→#93→#95）。KeychainService（service/account 分離・実 Keychain テスト）+ SettingsView のキー入力 UI。平文フィールドは履歴上存在せず移行パス不要と判断。統合メモ: #79 マージ後に APIKeyProviding 適合宣言 + DeepL 注入。マージ後: Done 化 + Issue #42 クローズ。
---
<!-- COMMENTS:END -->
