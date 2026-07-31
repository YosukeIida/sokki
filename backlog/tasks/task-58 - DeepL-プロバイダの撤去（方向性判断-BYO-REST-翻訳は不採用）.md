---
id: TASK-58
title: 'DeepL プロバイダの撤去（方向性判断: BYO REST 翻訳は不採用）'
status: In Progress
assignee: []
created_date: '2026-07-13 19:10'
updated_date: '2026-07-13 19:27'
labels:
  - Phase2.5
dependencies: []
priority: high
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ユーザー判断（2026-07-14）: REST の文単位翻訳 API（DeepL）をプロダクトに組み込むのは方向性として時代遅れ感があるため完全に撤去する。既定はオンデバイス Apple Translation、クラウド BYO は LLM ベースの Gemini Live のみ残す。初期調査 docs/realtime-translation-research.md の「除外: DeepL API」の結論に回帰する形（設計フェーズでキーの簡単さを理由に反転していた）。撤去範囲: (1) Sources/SokkiKit/Translation/BYO/DeepL*.swift 削除（APIKeyProviding は Gemini BYO 用に残す）、(2) TranslationProviderKind.deepL case 削除 + 永続化済み translationProvider="deepL" の .auto フォールバック、(3) SettingsView のピッカー/表示名・KeychainService の参照除去、(4) DeepL テスト削除 + 参照テスト更新、(5) docs 更新（spec.md に設計判断 D-18 追記・requirements.md・roadmap.md P25-6・translation-architecture.md）。TASK-56 は Coordinator の失敗差別化（Gemini 向け）に縮小。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 コード/テスト/設定 UI から DeepL 参照がゼロ
- [x] #2 永続化済み translationProvider=deepL が .auto にフォールバックしテストがある
- [x] #3 spec.md 設計判断ログに D-18 として記録されている
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 swift build が通る
- [x] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->



## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/111
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-07-13 19:27
---
PR #112 作成済み（feat/task-58-remove-deepl → main）: https://github.com/YosukeIida/sokki/pull/112

実装内容: DeepLLanguageMapping/DeepLTranslationProvider（+テスト）削除、TranslationProviderKind.deepL 削除、defaultCloudPreferenceOrder から除外、SettingsView のピッカー/表示名除去、KeychainService コメント置換。永続化済み `translationProvider="deepL"` は既存の `?? .auto` フォールバックで安全に解決されることを回帰テスト（TranslationSettingsMapperTests.removedDeepLProviderFallsBackToAuto）で明示化。spec.md に D-18 追記。requirements.md / docs/roadmap.md / docs/translation-architecture.md / docs/realtime-translation-research.md を更新。

検証: swift build エラー・新規警告ゼロ / swift test 326件全件 PASS（Snapshot 含む) / grep -rn -i deepl Sources/ ゼロ件。

レビュー状況: 未レビュー（マージ待ち）。マージ後に Done 化・Issue #111 クローズを行う。
---
<!-- COMMENTS:END -->
