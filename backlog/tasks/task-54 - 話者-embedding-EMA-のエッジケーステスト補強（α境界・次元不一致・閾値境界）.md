---
id: TASK-54
title: 話者 embedding EMA のエッジケーステスト補強（α境界・次元不一致・閾値境界）
status: To Do
assignee: []
created_date: '2026-07-13 12:53'
updated_date: '2026-07-13 13:16'
labels:
  - Phase3
  - test
dependencies: []
priority: low
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #78（TASK-28）の codex レビュー [MINOR] からの移送。未検証のエッジケース: (1) EMA の alpha 境界（0/1）、(2) embedding 次元不一致時の挙動（updateEmbedding に渡る新旧 embedding の長さが異なる場合）、(3) 声紋閾値ぎりぎり（0.81/0.83）での findOrCreate 分岐、(4) 並行呼び出し（actor 直列化で安全だが契約として固定されていない）。TASK-28 の PR 本文は「未解決点なし」と主張していたが実際にはテスト実効性の欠陥が2件あった（ミューテーションテストで実証）ため、残るカバレッジ欠けも同様に検証する価値がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 alpha 境界・次元不一致・閾値境界（0.81/0.83）のテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/107

PR #77 レビューからの追加項目: EMA テストが同一ベクトル再投入では計算誤りを検出できない問題（異方向ベクトルでの検証に強化）、graceful degradation テストが stop() 実経路を通らない問題。
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
