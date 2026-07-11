---
id: TASK-9.1
title: SessionList / SessionDetail へのデザイン横展開
status: Done
assignee: []
created_date: '2026-07-11 17:38'
updated_date: '2026-07-11 18:19'
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
- [x] #1 SessionList のモックが Manuscript / Console 両モードで作成されている
- [x] #2 SessionDetail のモックが Manuscript / Console 両モードで作成されている（タイムスタンプ・話者ラベル・話者カラー含む）
- [x] #3 モックのソースが docs/design/ に保存されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
recording-view-v2.html の CSS トークン（Manuscript/Console 両テーマ・書体・波形スタイル）を流用し、session-list-v1.html / session-detail-v1.html を作成。話者ラベルは ja 既定（話者A）+ ja/en トグル付き。実装は implementer-sonnet に委譲、メインでレビュー。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装は implementer-sonnet に委譲しメインでレビュー済み。v2 トークンを新規カスタムプロパティなしで完全流用（color-mix 合成のみ）。静的検証（タグ整合・JS 構文・外部参照なし・クラス定義突合）済み。実ブラウザでの見た目確認はユーザーにファイル送付済み（デザイン反復は親 TASK-9 で継続）。意図的差分: タイムスタンプを行頭配置（現行 SwiftUI は右端だが要件優先）、再生系は accent 色で録音色と区別。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
RecordingView v2 の CSS トークンを完全流用（新規カスタムプロパティなし）した session-list-v1.html / session-detail-v1.html を作成。両テーマ（Manuscript/Console）・話者ラベル ja/en・空状態のトグル付き。SessionDetail は行頭 mm:ss タイムスタンプ・話者カラーバー・エクスポートボタン（コピー/ファイル保存）・簡易再生バーを含む。
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 モックのソースを docs/design/ にコミットする
<!-- DOD:END -->
