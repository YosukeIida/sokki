---
id: TASK-42
title: dmg配布とGatekeeper回避手順のドキュメント化
status: Done
assignee: []
created_date: '2026-07-12 19:01'
updated_date: '2026-07-13 09:10'
labels:
  - Phase2
  - infra
milestone: m-1
dependencies:
  - TASK-10
references:
  - 'https://github.com/YosukeIida/sokki/issues/65'
priority: medium
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-10の決定（初期は無署名 dmg 配布、Developer ID 取得後に署名+公証へ移行）を実行に移す。GitHub Releases 経由で dmg 形式の配布物を作成できるようにし、無署名アプリのため発生する Gatekeeper 警告への対処手順を利用者向けにドキュメント化する。

Homebrew Cask 配布（TASK-37）は Developer ID 取得後の話として据え置き、当面はこの dmg 配布のみで運用する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitHub Releases から sokki.app を含む dmg をダウンロード・配布できる状態にする（ビルド→dmg作成手順を整備）
- [ ] #2 無署名アプリ実行時の Gatekeeper 警告と回避手順（システム設定からの許可 or xattr -d com.apple.quarantine 等）を README ないし配布ドキュメントに記載する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: scripts/make-dmg.sh（xcodebuild Release 無署名ビルド → hdiutil dmg 化、--adhoc-sign/--dry-run 等対応・外部ツール非依存）、docs/distribution.md（dmg ビルド・GitHub Releases 公開・Gatekeeper 回避手順 macOS 15/26 両対応）、README.md 新規作成。実機で dmg 生成・マウント・codesign 検証済み（無署名ビルドに entitlements 非埋め込みを実証）。司令塔レビュー APPROVE（MINOR: README テスト件数の固定値を削除済み）。PR #71 マージ済み（2026-07-13）。
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 21:55
---
実装完了・PR #71 作成済み（sonnet 実装・Fable レビュー済み・マージはユーザー承認待ち）。実 dmg 生成・マウント検証まで完了。重要な副産物: 無署名ビルドには entitlements が埋め込まれないことを実証（codesign -d --entitlements - が空）。TASK-11 の TCC 実機検証の前提情報。残タスク（ユーザー）: gh release create の実行とクリーン環境での Gatekeeper 警告実地確認。マージ後に Done 化と Issue #65 クローズ。
---
<!-- COMMENTS:END -->
