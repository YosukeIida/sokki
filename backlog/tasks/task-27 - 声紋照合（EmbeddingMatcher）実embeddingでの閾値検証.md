---
id: TASK-27
title: 声紋照合（EmbeddingMatcher）実embeddingでの閾値検証
status: In Progress
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-12 22:58'
labels:
  - Phase3
milestone: m-3
dependencies:
  - TASK-25
references:
  - 'https://github.com/YosukeIida/sokki/issues/46'
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
EmbeddingMatcherは実装済み・テスト通過済み。実embeddingを用いて閾値0.82の妥当性を検証する。GitHub Issue #46 (P3-4) 対応。P3-2（embedding取得配線）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 実 embeddingで閾値 0.82 の妥当性を検証する
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:58
---
実装完了・PR #84 マージ可能判定（sonnet・Fable レビュー・マージ順 #68→#77→#84）。閾値設定の実配線 + 類似度レポートハーネス（DEBUG 限定 Logger 出力）、73テスト。実測（ユーザー）: 実会話での分布確認→閾値0.82 の Open Question クローズ。マージ後: Done 化 + Issue #46 クローズ。
---
<!-- COMMENTS:END -->
