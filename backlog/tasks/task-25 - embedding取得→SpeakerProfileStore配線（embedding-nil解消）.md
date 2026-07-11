---
id: TASK-25
title: 'embedding取得→SpeakerProfileStore配線（embedding: nil解消）'
status: To Do
assignee: []
created_date: '2026-07-11 16:36'
updated_date: '2026-07-11 16:38'
labels:
  - Phase3
milestone: m-3
dependencies:
  - TASK-24
references:
  - 'https://github.com/YosukeIida/sokki/issues/44'
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
diarizationが256dim L2正規化embeddingを返し、SpeakerProfileStoreが実働（findOrCreate / EMA更新）するようにする。現状embedding: nilの空回りを解消する。GitHub Issue #44 (P3-2) 対応。P3-1（話者分離エンジン統合）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 diarizationが256dim L2正規化embeddingを返すこと
- [ ] #2 SpeakerProfileStoreがfindOrCreate / EMA更新で実働すること
<!-- AC:END -->
