---
id: TASK-12
title: Bothモード（マイク + システム同時）
status: Done
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-13 11:24'
labels:
  - Phase2
milestone: m-1
dependencies:
  - TASK-11
  - TASK-4
references:
  - 'https://github.com/YosukeIida/sokki/issues/31'
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
起動順を system（tap）先 → tapStreamDescription確定 → mic をtargetFormatで起動、停止は逆順とする。2ファイル別保存にする。GitHub Issue #31 (P2-2) 対応。P2-1（システム音声キャプチャ）およびP1-1（音声ディスク保存）に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 起動順system先→mic後、停止は逆順で実装されていること
- [ ] #2 micとsystemの音声が2ファイルに別々保存されること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
finalSummary: Both モード（マイク+システム同時録音・2ファイル保存）を実装。MicrophoneCapture/AudioStreamMerge 新規 + AudioCaptureManager 統合、primary(mic)/_system の2ファイル保存、SessionManager.deleteSession への削除一元化（UUID 経由で actor 再 fetch、@Model 境界規約準拠）。codex レビューは移送3系統で APPROVE: 時間軸2倍化・順序非決定性（PR 明記の MVP 近似）→ TASK-26 引き継ぎ、起動失敗時 session 残留（全モード共通既存）→ TASK-49/#102。2ファイルは別 writer + NSLock 直列化で並行書き込み競合なしを確認。PR #81 マージ済み（2026-07-13）。実機検証: 2系統同時録音の2ファイル生成。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-07-12 22:58
---
実装完了・PR #81 マージ可能判定（opus 実装・codex クロスレビュー + 修正・マージ順 #69→#76→#81）。system→mic 起動順/逆順停止/巻き戻し、2ファイル分離保存（primary=mic, _system 派生）、削除の SessionManager 一元化、86テスト。実機検証（ユーザー）: 2系統同時録音・oth 文字起こし・削除時の一覧更新。マージ後: Done 化 + Issue #31 クローズ + TASK-13 解放。
---
<!-- COMMENTS:END -->
