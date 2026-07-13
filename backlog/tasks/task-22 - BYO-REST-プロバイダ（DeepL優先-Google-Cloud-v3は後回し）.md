---
id: TASK-22
title: BYO REST プロバイダ（DeepL優先 / Google Cloud v3は後回し）
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-12 22:36'
labels:
  - Phase2.5
milestone: m-2
dependencies:
  - TASK-17
references:
  - 'https://github.com/YosukeIida/sokki/issues/41'
documentation:
  - docs/translation-architecture.md
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DeepLはREST+単純キーで実装容易なためAppleフォールバック先として先行実装する。Google Cloud v3はOAuth2/サービスアカウントが必要（生APIキー不可）のため後続とする。参照: translation-architecture.md §0-8。GitHub Issue #41 (P25-6) 対応。P25-1（TranslationProvider protocol）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DeepL RESTプロバイダが実装され、Apple未対応ペアのフォールバック先として動作すること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:36
---
実装完了・PR #79 マージ可能判定（sonnet 実装・Fable レビュー済み・#70 のスタック PR）。DeepL v2 provider + APIKeyProviding 抽象（TASK-23 が後で Keychain 実装を差す）。実機検証（ユーザー）: 実 DeepL キーでの接続。マージ後: Done 化 + Issue #41 クローズ。
---
<!-- COMMENTS:END -->
