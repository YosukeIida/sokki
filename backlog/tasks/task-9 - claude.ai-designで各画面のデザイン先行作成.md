---
id: TASK-9
title: claude.ai/designで各画面のデザイン先行作成
status: In Progress
assignee: []
created_date: '2026-07-11 16:34'
updated_date: '2026-07-11 17:39'
labels:
  - Phase1
  - design
milestone: m-0
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/28'
  - 'https://claude.ai/code/artifact/0e1c604b-af3d-4bad-a922-2aa341944a69'
documentation:
  - docs/design/recording-view-v2.html
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
録音/一覧/詳細/話者プロファイル/設定の各画面のビジュアルを確定し、実装用のデザイン基盤（トークン・共通コンポーネント）まで落とし込む親タスク。GitHub Issue #28 (P1-6) 対応。実作業はサブタスク TASK-9.1（一覧/詳細への横展開）、TASK-9.2（SwiftUI トークン + 共通コンポーネント化）、TASK-9.3（話者プロファイル/設定画面）で行う。

確定済み事項：
- RecordingView 視覚案 v4（ソース: docs/design/recording-view-v2.html）
- ライト=Manuscript（藍#2B4A78＋判子朱#C23B2C＋冷たい紙）/ ダーク=Console（鎮めたティール、mic #6E96C9・録音#D9534C）。システム外観に自動追従＋手動切替。
- 書体は両モード統一（SF Pro / ヒラギノ角ゴ、明朝不採用）。
- 波形=Voice Memos風（対称・細い棒＋隙間3px/4px）。モード対応（Mic/System=単一対称波形、Both=mic上・sys下）。セグメント(Mic/System/Both)はクリック切替。
- タイムスタンプは字幕行頭（mm:ss・等幅）。
- **話者ラベルはロケール追従（ja=話者A / en=Speaker A）に決定（2026-07-12）**。色は話者ごと固定、リネーム→声紋に紐づき次回以降は実名。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 話者ラベル表記を確定する（→ ロケール追従（ja=話者A / en=Speaker A）に決定済み・2026-07-12）
- [ ] #2 サブタスク TASK-9.1 / TASK-9.2 / TASK-9.3 がすべて完了している
<!-- AC:END -->



## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-07-12: 話者ラベルはユーザー確認のうえロケール追従（ja=話者A / en=Speaker A）に決定。実作業を TASK-9.1～9.3 に分割し、本タスクは親タスク化した。
<!-- SECTION:NOTES:END -->
