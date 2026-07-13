---
id: TASK-32
title: SRT / VTTエクスポート確認 + ファイル保存UI
status: In Progress
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 22:09'
labels:
  - Phase4
  - test
milestone: m-4
dependencies:
  - TASK-8
references:
  - 'https://github.com/YosukeIida/sokki/issues/51'
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実装済み（先取り）。実セッションで出力確認し、ファイル保存UIを追加する。GitHub Issue #51 (P4-1) 対応。P1-5（ファイル保存ダイアログ + Security-Scoped Bookmark）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 実セッションでSRT/VTT出力を確認する
- [ ] #2 ファイル保存UI（P1-5と共通の保存ダイアログ）から出力できること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:09
---
実装完了・PR #73 マージ可能判定（sonnet 実装・Fable レビュー済み・マージはユーザー承認待ち）。発見した実バグ: ファイル保存が Markdown 固定で SRT/VTT を保存する手段がなかった→全形式対応に修正。実機検証（ユーザー）: 保存ダイアログからの SRT/VTT 出力確認。マージ後: Done 化 + Issue #51 クローズ。TASK-33 は本ブランチ上にスタックして着手済み。
---
<!-- COMMENTS:END -->
