---
id: TASK-50
title: SpeechAnalyzerEngine の hardening（後片付け・isAvailable・Settings UX・言語統合）
status: To Do
assignee: []
created_date: '2026-07-13 10:40'
updated_date: '2026-07-13 10:40'
labels:
  - Phase4
dependencies: []
priority: medium
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #82（TASK-35）の codex レビュー指摘からの移送 + doc-1 統合タスク。(1) setTranscriptionLanguage(String?) async の protocol 実装（設定文字列→BCP47 Locale 変換ヘルパー。現状 ja-JP ハードコード。約10〜20行・単一ファイル）。(2) batch 経路の collector Task が makeAnalyzerInput throw 時に孤立するリーク解消・try? の握り潰し解消・onTermination の analyzer 後片付け。(3) SpeechTranscriber.isAvailable によるハード能力チェックを factory/SettingsView で共通化（現状 OS バージョンのみ判定で非対応ハードでは prepare() throw）。(4) SpeechAnalyzer 選択時に Whisper モデル Section を非表示・ロード文言の engine-neutral 化。macOS 26 実機での動作評価とあわせて実施。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 setTranscriptionLanguage が protocol シグネチャで実装され言語設定が反映される
- [ ] #2 batch 経路のエラー時に collector Task がリークしない
- [ ] #3 非対応ハードで SpeechAnalyzer が選択肢から除外またはフォールバックする
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ミラー Issue: https://github.com/YosukeIida/sokki/issues/103
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
