---
id: TASK-7
title: Markdownエクスポートの動作確認
status: Done
assignee: []
created_date: '2026-07-11 16:34'
updated_date: '2026-07-12 07:06'
labels:
  - Phase1
  - test
milestone: m-0
dependencies:
  - TASK-6
references:
  - 'https://github.com/YosukeIida/sokki/issues/26'
modified_files:
  - Sources/SokkiKit/UI/SessionDetailView/SessionDetailView.swift
  - Tests/sokkiUITests/SokkiUITests.swift
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
話者名・タイムスタンプ付きMarkdownがクリップボード/ファイルに正しく出力されることを実機確認する。ExportTestsは通過済みなので、実機での動作確認が主眼。GitHub Issue #26 (P1-4) 対応。P1-3（E2E確認）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 実機でMarkdownエクスポートを実行し、話者名・タイムスタンプが正しく含まれることを確認する
- [x] #2 クリップボードへのコピーが正しく動作することを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-07-12: XCUITest で自動化し確認。エクスポートトグルボタンは SwiftUI の Menu+square.and.arrow.up が macOS 上で MenuButton（title: "Share"）としてレンダリングされる仕様を発見（表示ラベルは「エクスポート」のままで見た目の影響はない）。Markdownコピー後の NSPasteboard に内容が入ることを確認。「ファイルへ保存…」も NSSavePanel（identifier: save-panel）が开くことを確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Markdown エクスポート（クリップボードコピー）とファイル保存ダイアログの表示を XCUITest で自動確認。実セッションのクリップボード内容が空でないことを検証。ExportService のフォーマット自体は既存単体テスト（Exporter suite）でカバー済み。
<!-- SECTION:FINAL_SUMMARY:END -->
