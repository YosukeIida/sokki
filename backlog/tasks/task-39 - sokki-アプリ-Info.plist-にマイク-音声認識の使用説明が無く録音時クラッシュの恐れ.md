---
id: TASK-39
title: sokki アプリ Info.plist にマイク/音声認識の使用説明が無く録音時クラッシュの恐れ
status: Done
assignee: []
created_date: '2026-07-11 19:02'
updated_date: '2026-07-11 20:40'
labels:
  - Phase1
  - bug
milestone: m-0
dependencies: []
references:
  - project.yml
  - docs/handover.md
  - 'https://github.com/YosukeIida/sokki/issues/62'
modified_files:
  - project.yml
  - Info.plist
priority: high
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実機起動の事前調査（2026-07-12）で発見。ビルド済み sokki.app（DerivedData）の Info.plist に NSMicrophoneUsageDescription が無い。macOS ではこのキーが無いとマイクアクセス時にアプリがクラッシュするため、録音が一切できない。テストでは検出不能な実行時バグ（TASK-6 の E2E を必ずブロックする）。

根本原因（確定）: project.yml の sokki アプリターゲットの info ブロックが `path: Info.plist` のみで `properties:` を持たない（SokkiKit も同様に path のみ）。そのため xcodegen が生成する Info.plist に使用目的キーが含まれない。

修正方針: project.yml の sokki ターゲット（HEAD 版で 51行目付近 `sokki:` → 56行目 `info: path: Info.plist`）の info に properties を追加し、NSMicrophoneUsageDescription と NSSpeechRecognitionUsageDescription（および必要なら CFBundleDisplayName / LSMinimumSystemVersion 等）を記述する。その後 `xcodegen generate` → クリーンビルド → `plutil -p sokki.app/Contents/Info.plist | grep -i microphone` でキーの存在を確認。entitlements（audio-input 等 4 権限）は既に別途 sokki.entitlements に入っているので触らない。

補足: 調査中にツール出力が不安定になり、一時 project.yml に「マイクキーがある」「依存が重複している」と誤って見えたが、安定後の `git show HEAD:project.yml` で確認したところ、マイクキーは元から無く、settings/info/dependencies の複数出現は 3 ターゲット（sokki / SokkiKit / sokkiTests）ぶんの正常構造だった（project.yml 自体は破損していない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 project.yml の sokki ターゲット info.properties に NSMicrophoneUsageDescription と NSSpeechRecognitionUsageDescription が追加されている
- [x] #2 xcodegen generate 後のビルド成果物 sokki.app/Contents/Info.plist に両キーが存在する（plutil で確認）
- [ ] #3 実機で録音を開始してもクラッシュせず、マイク許可ダイアログが出る
- [x] #4 entitlements の 4 権限が引き続き保持されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
修正後、Xcode MCP の BuildProject はキャッシュされた旧 Info.plist（6/26付）を使い回す増分ビルドをしてしまい、一見成功したように見えて実は反映されていなかった。`xcodebuild clean build` で強制リビルドして修正を確認。以後 project.yml 変更後は xcodegen generate のみでなく、Xcode でのクリーンビルドも検討するべき（リソース変更がビルドシステムに拾い切れないことがある）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
project.yml の sokki ターゲット info に properties（NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription）を追加。xcodegen generate → xcodebuild clean build で再ビルドし、生成された sokki.app/Contents/Info.plist に両キーが存在すること、entitlements 4権限も保持されていることを確認済み。AC#3（実機録音でクラッシュしない）はユーザーの手動確認待ち。
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 swift build が通る
- [ ] #2 swift test で本変更起因の失敗がない（既知の Snapshot 失敗 4 件は除外可）
- [ ] #3 project.yml 変更時は xcodegen generate を実行し entitlements の 3 権限（audio-input / screen-capture / network.client）が保持されていることを確認する
- [ ] #4 対応する GitHub Issue がある場合は完了時に gh issue close でクローズして backlog と同期する
<!-- DOD:END -->
