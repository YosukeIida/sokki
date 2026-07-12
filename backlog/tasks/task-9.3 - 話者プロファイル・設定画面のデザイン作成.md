---
id: TASK-9.3
title: 話者プロファイル・設定画面のデザイン作成
status: Done
assignee: []
created_date: '2026-07-11 17:38'
updated_date: '2026-07-11 18:38'
labels:
  - Phase1
  - design
milestone: m-0
dependencies:
  - TASK-9.1
references:
  - 'https://github.com/YosukeIida/sokki/issues/60'
parent_task_id: TASK-9
priority: low
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
P1-6 スコープの残り2画面（SpeakerProfileView / SettingsView）のビジュアルを、確定済みの2モードデザイン（Manuscript / Console）に準拠して作成する。話者ラベルはロケール追従（ja=話者A / en=Speaker A）。親タスク: TASK-9（P1-6 / GitHub #28）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 話者プロファイル画面のモックが両モードで作成されている
- [x] #2 設定画面のモックが両モードで作成されている
- [x] #3 モックのソースが docs/design/ に保存されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
既存モック3点のトークン・構成を流用し、speaker-profile-v1.html / settings-v1.html を作成。SpeakerProfileView は一覧・名前編集・出現回数・削除（TASK-30 の先行ビジュアル）、SettingsView は現行実装の項目 + 外観切替（システム/ライト/ダーク、TASK-9.2 と整合）。実装は implementer-sonnet に委譲、メインでレビュー。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装は implementer-sonnet に委譲しメインでレビュー済み。新規トークンなし（4話者以上の色は color-mix 暂定合成、オープンクエスチョンのまま）。意図的変更: Settings を独立 TabView からサイドバー付きシェルへ統合（最終採否は実装側判断）。検出された仕様乖離: SpeakerProfileStore.swift:70 の自動命名が「話者 1」形式でロケール追従仕様と不一致 → 別タスク化した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
speaker-profile-v1.html（登録済み実名/未登録話者の混在・リネーム動作・削除は見た目のみ=TASK-30 委ね・空状態付き）と settings-v1.html（現行3タブ+外観タブ先頭追加・外観ピッカーが実際にテーマ切替・システム追従の挙動を再現）を作成。トークンは既存モックから完全流用（新規カスタムプロパティなし）。
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 モックのソースを docs/design/ にコミットする
<!-- DOD:END -->
