---
id: TASK-6
title: 録音一覧・詳細画面のE2E動作確認
status: Done
assignee: []
created_date: '2026-07-11 16:34'
updated_date: '2026-07-12 07:06'
labels:
  - Phase1
  - test
milestone: m-0
dependencies:
  - TASK-4
  - TASK-39
references:
  - 'https://github.com/YosukeIida/sokki/issues/25'
documentation:
  - docs/handover.md
modified_files:
  - Sources/SokkiKit/UI/RecordingView/RecordingView.swift
  - Sources/SokkiKit/UI/ContentView.swift
  - Sources/SokkiKit/UI/SessionListView/SessionListView.swift
  - Tests/sokkiUITests/SokkiUITests.swift
  - project.yml
priority: high
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Xcode ⌘Rで実機動作を確認する：マイク録音→文字起こし→一覧で録音長表示→詳細→セグメント表示まで通し確認。~/Library/Application Support/sokki/recordings/*.m4a の生成も確認する。GitHub Issue #25 (P1-3) 対応。P1-1（音声保存）に依存。現在の再開ポイント（次にやること最優先）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Xcode ⌘Rでマイク録音が開始・停止できること
- [x] #2 文字起こし結果がSessionDetailに表示されること
- [x] #3 SessionListに正しい録音長が表示されること
- [x] #4 録音ファイル（.m4a）がディスクに生成されていることを確認すること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-07-12: 実機 E2E の前に TASK-39（マイク使用説明欠落で録音クラッシュ）の修正が必須。現状のビルド成果物は録音ボタンで落ちる見込み。

2026-07-12: 実機 E2E を XCUITest で自動化し確認済み（sokkiUITests ターゲット新規）。testRecordStopAndAppearsInSessionList が実際にマイク録音を開始・停止し、一覧にセッションが追加されることを確認。アクセシビリティビューの実スナップショットで「Hello, I'm a」「Can I hear you?」の実際の文字起こし結果が SessionDetail に表示されていることを目視確認。録音ファイル（.m4a）も自動テスト実行ごとにディスクに生成されることを ls で確認。既知の制約（Phase1）: 見えたているとおり録音は30秒窓+5秒オーバーラップのバッチ処理でリアルタイムではなく、重複区間が二重表示されることがある（TASK-14/Phase2 で置換予定）。言語指定は未実装（別途タスク化推奨）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
実機 E2E を XCUITest（新規 sokkiUITests ターゲット）で自動化し確認完了。マイク録音開始→約90秒録音継続（経過時間表示更新を確認）→停止→フラッシュ処理完了→録音一覧にセッション追加→詳細画面で実際の文字起こし結果表示→Markdownコピーでクリップボードに内容が入ることを検証。録音ファイル（.m4a）もテスト実行ごとにディスクへ生成されることを確認。RecordingView/ContentView/SessionListView の主要ボタンに accessibility identifier を追加。既知の制約（30秒窓+5秒オーバーラップによる非リアルタイム・二重表示、言語設定未実装）はユーザー確認済みで別途対応（TASK-14等）。
<!-- SECTION:FINAL_SUMMARY:END -->
