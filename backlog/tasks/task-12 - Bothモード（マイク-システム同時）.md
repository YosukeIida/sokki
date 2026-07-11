---
id: TASK-12
title: Bothモード（マイク + システム同時）
status: To Do
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-11 16:38'
labels:
  - Phase2
milestone: m-1
dependencies:
  - TASK-11
  - TASK-4
references:
  - 'https://github.com/YosukeIida/sokki/issues/31'
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
起動順を system（tap）先 → tapStreamDescription確定 → mic をtargetFormatで起動、停止は逆順とする。2ファイル別保存にする。GitHub Issue #31 (P2-2) 対応。P2-1（システム音声キャプチャ）およびP1-1（音声ディスク保存）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 起動順system先→mic後、停止は逆順で実装されていること
- [ ] #2 micとsystemの音声が2ファイルに別々保存されること
<!-- AC:END -->
