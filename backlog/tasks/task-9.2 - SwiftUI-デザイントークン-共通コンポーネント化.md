---
id: TASK-9.2
title: SwiftUI デザイントークン + 共通コンポーネント化
status: To Do
assignee: []
created_date: '2026-07-11 17:38'
updated_date: '2026-07-11 17:39'
labels:
  - Phase1
  - design
milestone: m-0
dependencies:
  - TASK-9.1
references:
  - 'https://github.com/YosukeIida/sokki/issues/59'
parent_task_id: TASK-9
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
確定したデザイン（2モードのカラーパレット・書体・波形スタイル・タイムスタンプ・話者ラベル）を SokkiKit 内のデザイントークン（色・タイポグラフィ定数）と共通コンポーネントとして実装する。話者ラベルはロケール追従（ja=話者A / en=Speaker A）とし、String Catalog 等のローカライズ基盤で実装する。システム外観への自動追従＋手動切替に対応する。親タスク: TASK-9（P1-6 / GitHub #28）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 カラー・タイポグラフィがデザイントークンとして SokkiKit に定義されている
- [ ] #2 話者ラベルがロケール追従（ja=話者A / en=Speaker A）で実装されている
- [ ] #3 システム外観自動追従と手動切替が動作する
- [ ] #4 RenderPreview で Manuscript / Console 両モードの表示を確認済み
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
