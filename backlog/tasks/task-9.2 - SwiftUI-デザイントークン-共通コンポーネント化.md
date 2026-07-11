---
id: TASK-9.2
title: SwiftUI デザイントークン + 共通コンポーネント化
status: Done
assignee: []
created_date: '2026-07-11 17:38'
updated_date: '2026-07-11 18:34'
labels:
  - Phase1
  - design
milestone: m-0
dependencies:
  - TASK-9.1
references:
  - 'https://github.com/YosukeIida/sokki/issues/59'
modified_files:
  - Sources/SokkiKit/DesignSystem/SokkiTokens.swift
  - Sources/SokkiKit/DesignSystem/SokkiAppearance.swift
  - Sources/SokkiKit/DesignSystem/SpeakerLabel.swift
  - Sources/SokkiKit/DesignSystem/DesignSystemComponents.swift
  - Sources/SokkiKit/DesignSystem/DesignSystemGallery.swift
  - Tests/sokkiTests/DesignSystemTests.swift
  - Sources/SokkiKit/UI/ContentView.swift
  - Sources/SokkiKit/UI/SettingsView/SettingsView.swift
parent_task_id: TASK-9
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
確定したデザイン（2モードのカラーパレット・書体・波形スタイル・タイムスタンプ・話者ラベル）を SokkiKit 内のデザイントークン（色・タイポグラフィ定数）と共通コンポーネントとして実装する。話者ラベルはロケール追従（ja=話者A / en=Speaker A）とし、String Catalog 等のローカライズ基盤で実装する。システム外観への自動追従＋手動切替に対応する。親タスク: TASK-9（P1-6 / GitHub #28）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 カラー・タイポグラフィがデザイントークンとして SokkiKit に定義されている
- [x] #2 話者ラベルがロケール追従（ja=話者A / en=Speaker A）で実装されている
- [x] #3 システム外観自動追従と手動切替が動作する
- [x] #4 RenderPreview で Manuscript / Console 両モードの表示を確認済み
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
モック3点（recording-view-v2 / session-list-v1 / session-detail-v1）の CSS トークンを SwiftUI へ移植する。Sources/SokkiKit/DesignSystem/ に SokkiTokens（両テーマの色・話者パレット・波形定数）、外観オーバーライド（@AppStorage + preferredColorScheme、既定はシステム追従）、Environment 経由のトークン注入、SpeakerLabel（コード判定によるロケール追従。String Catalog は SPM/xcodegen 二重リソースパイプラインを避けるため今回は不採用の設計判断）、TimestampText / SpeakerColorBar コンポーネント、ギャラリー #Preview を実装。SettingsView に外観 Picker を追加。既存画面の再スタイリングは後続タスク。実装は implementer-opus に委譲、メインでレビュー。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装は implementer-opus に委譲しメインでレビュー済み（指摘なし）。メインで xcodegen generate を実行し新ディレクトリを xcodeproj に反映（entitlements 4 権限保持を確認）。RenderPreview で Manuscript/Console 両モードのギャラリーをメインが目視検証済み。既知の制限: preferredColorScheme はメインウィンドウのみに効き Settings ウィンドウは OS 外観のまま（Phase1 許容）。String Catalog 不採用（コード内ロケール判定）は設計判断としてコードコメントに記録済み。swift test 48 件全 pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sources/SokkiKit/DesignSystem/ を新設し、モック CSS の全17テーマトークン+話者3色を SokkiTokens（manuscript/console）として移植（hex リテラルで目視照合可能）。SokkiAppearance（システム/ライト/ダーク、@AppStorage + preferredColorScheme）、Environment 注入の sokkiDesignSystem() モディファイア、SpeakerLabel（ロケール追従 ja=話者A / en=Speaker A、bijective base-26）、TimestampText / SpeakerColorBar、両モードのギャラリー #Preview を実装。SettingsView に外観 Picker 追加。テスト14件追加（計48件全 pass）、RenderPreview で両モード検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 swift build が通る
- [x] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [x] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [x] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
