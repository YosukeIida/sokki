---
id: TASK-34
title: ファイルインポート（.mp4/.m4a/.wav/.mp3）
status: In Progress
assignee: []
created_date: '2026-07-11 16:37'
updated_date: '2026-07-12 23:22'
labels:
  - Phase4
milestone: m-4
dependencies:
  - TASK-26
references:
  - 'https://github.com/YosukeIida/sokki/issues/53'
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AudioFileImporterを実装し、既存ファイルを文字起こし・話者分離できるようにする。GitHub Issue #53 (P4-3) 対応。P3-3（WhisperKitセグメントとdiarizationのマージ）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AudioFileImporterが.mp4/.m4a/.wav/.mp3を取り込めること
- [ ] #2 取り込んだファイルが文字起こし・話者分離されること
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 23:22
---
実装完了・PR #91 マージ可能判定（sonnet・Fable レビュー・マージ順 #87系→#91）。AudioFileImporter（NSOpenPanel→コピー/mp4音声抽出→バッチ文字起こし→diarization、失敗時ロールバック）、87テスト。実機検証（ユーザー）: 実 mp3/mp4 の取り込み。マージ後: Done 化 + Issue #53 クローズ。
---
<!-- COMMENTS:END -->
