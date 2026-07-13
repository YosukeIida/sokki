---
id: TASK-37
title: Homebrew Cask配布 + Gatekeeper回避ドキュメント
status: To Do
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 21:33'
labels:
  - Phase5
  - infra
milestone: m-5
dependencies:
  - TASK-10
references:
  - 'https://github.com/YosukeIida/sokki/issues/56'
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
brew install --cask sokkiで導入可能にする。署名方針（P2-0）と整合させる。GitHub Issue #56 (P5-2) 対応。P2-0（配布方針の意思決定）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 brew install --cask sokkiで導入できること
- [ ] #2 署名方針（P2-0）と整合していること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 21:33
---
【2026-07-13 オーケストレーション判断】doc-1 の方針通り、本タスクは Developer ID Program 取得後まで保留とする。Phase2〜5 並列実装セッションのスコープから除外（TASK-42 の dmg 配布ドキュメントが先行する）。
---
<!-- COMMENTS:END -->
