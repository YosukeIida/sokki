---
id: TASK-8
title: エクスポートにファイル保存ダイアログ + Security-Scoped Bookmark
status: Done
assignee: []
created_date: '2026-07-11 16:34'
updated_date: '2026-07-11 18:16'
labels:
  - Phase1
milestone: m-0
dependencies:
  - TASK-7
references:
  - 'https://github.com/YosukeIida/sokki/issues/27'
modified_files:
  - Sources/SokkiKit/Export/ExportSaveService.swift
  - Sources/SokkiKit/Export/ExportDirectoryBookmarkStore.swift
  - Sources/SokkiKit/UI/SessionDetailView/SessionDetailView.swift
  - Tests/sokkiTests/ExportSaveServiceTests.swift
  - project.yml
  - sokki.entitlements
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
クリップボードコピーだけでなく、保存先を選択できるファイル保存ダイアログに対応する。Sandbox下でも再アクセス可能なようSecurity-Scoped Bookmarkを実装する。GitHub Issue #27 (P1-5) 対応。P1-4（Markdownエクスポート確認）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 NSSavePanel等でユーザーが保存先を選択できること
- [x] #2 Security-Scoped Bookmark による保存先の記憶・復元が実装され、sandbox 有効化時にそのまま機能する2段構え（.withSecurityScope 優先→通常ブックマーク）になっている（sandbox 自体は Phase1 では無効の設計判断）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 既存の ExportService / SessionDetailView / AppSettingsModel を読む
2. ExportSaveService（NSSavePanel + Security-Scoped Bookmark、非 sandbox フォールバック付き）を SokkiKit/Export に新規実装
3. SessionDetailView に「ファイルへ保存…」を追加
4. project.yml に com.apple.security.files.user-selected.read-write を追加し xcodegen generate（entitlements 4 権限保持を確認）
5. ブックマーク保存ロジックとファイル名整形を単体テスト化
※ sandbox 自体は Phase1 では有効化しない（設計判断: E2E への影響回避）。実装は implementer-sonnet に委譲、メインでレビュー。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装は implementer-sonnet に委譲しメインでレビュー済み。2段構えブックマーク（.withSecurityScope→通常）、stale 時再生成、start/stop のガードを確認。既知の改善余地: 書き込み失敗が無言で nil になる（エラー UI なし、MVP 許容）。swift test 34 件全 pass（既知 Snapshot 失敗も今回は未発生）。xcodegen 再生成後も entitlements 4 権限保持を検証済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NSSavePanel によるファイル保存を実装。ExportSaveService（@MainActor、ファイル名サニタイズ付き）と ExportDirectoryBookmarkStore（UserDefaults 保存、.withSecurityScope 優先→通常ブックマークの2段構え、stale 再生成）を SokkiKit/Export に新規追加し、SessionDetailView のエクスポートメニューに「ファイルへ保存…」を追加。project.yml に user-selected.read-write entitlement を追加（app-sandbox は Phase1 では有効化しない設計判断）。単体テスト7件追加、swift test 34件全 pass。
<!-- SECTION:FINAL_SUMMARY:END -->
