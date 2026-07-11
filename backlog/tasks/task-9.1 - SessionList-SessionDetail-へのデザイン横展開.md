---
id: TASK-9.1
title: SessionList / SessionDetail へのデザイン横展開
status: To Do
assignee: []
created_date: '2026-07-11 17:38'
updated_date: '2026-07-11 17:39'
labels:
  - Phase1
  - design
milestone: m-0
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/58'
documentation:
  - docs/design/recording-view-v2.html
parent_task_id: TASK-9
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RecordingView v4 で確定した2モードデザイン（ライト=Manuscript: 藍#2B4A78＋判子朱#C23B2C＋冷たい紙 / ダーク=Console: 鎮めたティール、mic #6E96C9・録音#D9534C）を SessionList・SessionDetail に横展開したモックを作成する。書体は両モード統一（SF Pro / ヒラギノ角ゴ）、タイムスタンプは行頭 mm:ss 等幅、話者ラベルはロケール追従（ja=話者A / en=Speaker A、色は話者ごと固定）。親タスク: TASK-9（P1-6 / GitHub #28）。参照モック: docs/design/recording-view-v2.html。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SessionList のモックが Manuscript / Console 両モードで作成されている
- [ ] #2 SessionDetail のモックが Manuscript / Console 両モードで作成されている（タイムスタンプ・話者ラベル・話者カラー含む）
- [ ] #3 モックのソースが docs/design/ に保存されている
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 モックのソースを docs/design/ にコミットする
<!-- DOD:END -->
