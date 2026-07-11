---
id: TASK-10
title: 配布方針の意思決定（ブロッカー）
status: To Do
assignee: []
created_date: '2026-07-11 16:35'
labels:
  - Phase2
  - infra
milestone: m-1
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/29'
priority: high
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Core Audio Taps（ProcessTap）と署名/配布（NFR-5: コード署名なし方針）が両立するかを検証し、Developer ID署名 / App Store / 署名なしのいずれかを確定する。Phase2着手のブロッカーであり、Open Questionを1つ閉じる。GitHub Issue #29 (P2-0) 対応。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Core Audio Taps使用時の署名要件（entitlement/notarization等）を調査し、制約を文書化する
- [ ] #2 配布方式（Developer ID署名 / App Store / 署名なし）をひとつに確定し、requirements.mdのOpen Questionを閉じる
<!-- AC:END -->
