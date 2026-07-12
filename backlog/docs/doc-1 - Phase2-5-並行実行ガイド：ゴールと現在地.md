---
id: doc-1
title: Phase2-5 並行実行ガイド：ゴールと現在地
type: guide
created_date: '2026-07-12 20:57'
tags:
  - roadmap
  - parallel-execution
  - phase2
  - phase3
  - phase4
  - phase5
---
## このドキュメントの役割

次セッションで Phase2〜5 の複数タスクを並行して進める際、**最初に読むエントリーポイント**。「今どこまで終わっていて、次に何を並行で始められるか」をここで確認してから `backlog task view <N>` で個々のタスクへ進む。

設計根拠・完了基準の詳細は `docs/roadmap.md`（スナップショット）。タスクの状態・依存関係の正本は backlog（このドキュメントも含め `backlog/` 配下）。

## ゴール（各 Phase の目的、詳細は roadmap.md）

| Phase | ゴール | 状態 |
|---|---|---|
| Phase 1 | MVP仕上げ：録音→文字起こし→保存→表示→エクスポート | ✅ 完了（TASK-1〜10, 9.1-9.3, 39, 40） |
| Phase 2 | システム音声（Core Audio Taps）+ リアルタイム文字起こし | 未着手 |
| Phase 2.5 | リアルタイム翻訳（TranslationProvider 抽象 + Apple Translation 既定） | 未着手 |
| Phase 3 | 話者分離 + 声紋永続化（**差別化の本丸**、現状 `embedding: nil` で空回り） | 未着手 |
| Phase 4 | エクスポート拡充・音声再生・ファイルインポート | 未着手 |
| Phase 5 | 配布・プライバシー | 一部完了（配布方針は TASK-10 で決定済み） |
| Phase 6 | LLM後処理（要約等） | **着手しない**（スコープ外） |

## 現在地（2026-07-13 時点）

- Done: TASK-1〜10, TASK-9.1〜9.3, TASK-39, TASK-40（Phase1 MVP + 配布方針決定）
- roadmap.md の34タスク（P1-1〜P5-2）は全て backlog の TASK-4〜TASK-37 に1対1で対応済み（依存関係も概ね一致、監査済み・2026-07-13）
- 追加タスク: TASK-38（話者命名ロケール統一）、TASK-41（文字起こし言語設定）、TASK-42（dmg配布）、TASK-43（デザイントークン適用・v3モック起因）

## 今すぐ並行着手可能なタスク（依存が全て Done）

以下は互いに依存せず、依存タスクも全て解決済み。並行して着手できる（ただしファイル競合は都度 backlog task view で確認）。

| TASK | 内容 | 触る主なファイル | 備考 |
|---|---|---|---|
| **TASK-11**（P2-1） | Core Audio Taps 本体実装 | `AudioCaptureManager.swift` | **Phase2 の入口。最重要かつ最大の不確実性** — 無署名ビルドで TCC prompt が発火するか未検証（TASK-10 調査結果）。ここで詰まると Phase2 全体・Developer ID 取得判断に波及する。最初に着手すべき |
| **TASK-17**（P25-1） | TranslationProvider protocol + ルーティング層 | 新規ファイル群（`Translation/`） | Phase2.5 の入口。TASK-11 と独立、並行可 |
| **TASK-24**（P3-1） | 話者分離エンジン統合（FluidAudio） | 新規ファイル群（`Diarization/`） | Phase3 の入口。TASK-11/17 と独立、並行可 |
| **TASK-32**（P4-1） | SRT/VTT エクスポート確認 + ファイル保存UI | `ExportSaveService.swift`, `SessionDetailView.swift` | 実装済み機能の確認が中心、軽量 |
| **TASK-33**（P4-2） | AudioPlaybackController 新規 + セグメント同期再生 | 新規ファイル + `SessionDetailView.swift` | 新規コンポーネント中心 |
| **TASK-38** | 話者自動命名をロケール追従に統一 | `SpeakerLabel.swift` 等 | 独立・軽量 |
| **TASK-41** | 文字起こし言語設定を追加 | `SettingsView`, `TranscriptionEngine` 系 | 独立 |
| **TASK-42** | dmg配布 + Gatekeeper回避ドキュメント化 | ドキュメント中心、コード変更少 | TASK-10 決定の実行タスク |
| **TASK-43** | 既存画面にデザイントークン適用 | `RecordingView.swift`, `SessionListView.swift`, `SessionRowView.swift`, `SegmentListView.swift`, `SessionDetailView.swift` | UI全般に触るため範囲が広い。TASK-32/33 と `SessionDetailView.swift` で競合する可能性 |
| TASK-15（P2-5, LOW） | 会議自動検出（任意） | 新規ファイル | 優先度低・前倒し可能な独立タスク |
| TASK-37（P5-2） | Homebrew Cask 配布 | `project.yml` | **実質保留** — TASK-10 決定によりDeveloper ID Program 取得後まで着手を待つのが妥当 |

**ファイル競合の注意**: TASK-32・TASK-33・TASK-43 はいずれも `SessionDetailView.swift` に触れうる。3つを完全並列で進める場合は、着手前に互いの変更範囲を確認するか、順序を1本化すること。

## 依存関係マップ（何が終わると何が解放されるか）

```
TASK-11 (P2-1) 完了 → TASK-12(P2-2 Bothモード), TASK-13(P2-3 レベルメーター), TASK-14(P2-4 リアルタイム文字起こし) が解放
TASK-14 (P2-4) 完了 → TASK-16(P2-6 後処理), TASK-19(P25-3 翻訳字幕UI), TASK-26(P3-3 segmentマージ), TASK-35(P4-4 SpeechAnalyzer) が解放
TASK-17 (P25-1) 完了 → TASK-18(P25-2 Apple Translation), TASK-20(P25-4 翻訳トグル), TASK-21(P25-5 Gemini), TASK-22(P25-6 DeepL) が解放
TASK-20 (P25-4) 完了 → TASK-23(P25-7 Keychain), TASK-36(P5-1 プライバシーモードUI) が解放
TASK-24 (P3-1) 完了 → TASK-25(P3-2 embedding配線), TASK-26(P3-3 segmentマージ、TASK-14とのAND依存) が解放
TASK-25 (P3-2) 完了 → TASK-27(P3-4 閾値検証), TASK-28(P3-5 永続化) が解放
TASK-26 (P3-3) 完了 → TASK-29(P3-6 話者カラーバー), TASK-31(P3-8 DER実測), TASK-34(P4-3 ファイルインポート) が解放
TASK-28 (P3-5) 完了 → TASK-30(P3-7 SpeakerProfileView UI) が解放
```

## 次セッションでの動き方（提案）

1. `backlog task list --status "To Do"` で状態を再確認（このドキュメント作成後に進捗があれば更新されているはず）。
2. 上表の「今すぐ並行着手可能」から、担当したいタスクをピック。**TASK-11 は最優先**——ここの実機検証結果（無署名でTCC promptが発火するか）が Phase2 全体の見通しを左右する。
3. 各タスクの詳細は `backlog task view <N>` で確認してから着手（本ドキュメントは概要のみ）。
4. 完了したら CLAUDE.md の同期ルールに従い backlog を Done にし、対応 Issue をクローズ。このドキュメントの「現在地」セクションは古くなるので、次回に大きな進捗があれば更新するか、内容が古いと判断したら読み捨ててよい（スナップショットであり正本ではない）。
