---
id: doc-1
title: Phase2-5 並行実行ガイド：ゴールと現在地
type: guide
created_date: '2026-07-12 20:57'
updated_date: '2026-07-13 00:00'
tags:
  - roadmap
  - parallel-execution
  - phase2
  - phase3
  - phase4
  - phase5
---
## このドキュメントの役割

Phase2〜5 並行実行のエントリーポイント。**2026-07-13 の並列実装セッションで実装対象の全タスクが完了し、PR 29本がマージ待ちになった。** 現在の正本情報はこのドキュメントの「現在地」と各 backlog タスクのコメント。

## 現在地（2026-07-13 並列実装セッション後）

- **実装完了・PR 作成済み（マージはユーザー承認待ち）**: TASK-11〜36, 38, 41, 42（TASK-37 を除く全 To Do タスク）
- **残タスク**: TASK-43（デザイントークン適用）= 全 UI ファイルに触れるため**下記の全 PR マージ後に着手**。TASK-37（Homebrew Cask）= Developer ID 取得まで保留
- 実装体制: opus/sonnet サブエージェント + codex（gpt-5.6-sol）並列実装、codex/code-reviewer クロスレビュー、Fable オーケストレーション。全 PR はレビュー済み（高リスク PR は codex クロスレビュー 1〜2周 + 修正対応済み）

## PR マージ順（重要 — スタック構造のため順序厳守）

マージのたびに次のスタック PR の base を main に付け替えること（GitHub が自動で行わない場合）。

1. **独立系（main 直系、任意順）**: #67(38) → #71(42) → #72(41) → #74(15)
2. **エクスポート/再生系**: #73(32) → #75(33)
3. **音声キャプチャ系**: #69(11) → #76(14) → #81(12) → #85(16), #89(13) / #76 の後に #82(35)
4. **話者分離系**: #68(24) → #77(25) → #78(28), #84(27) → #83(30) / #78 の後 #87(26) → #88(29), #90(31), #91(34)
5. **翻訳系**: #70(17) → #79(22), #86(21), #93(20) → #94(36), #95(95=23) / **#80(18) は実機 PoC 成功が前提条件** → その後 #92(19)

## マージ後の統合タスク（小整理、各1〜2行〜小規模）

- SpeechAnalyzerEngine を #72 の setTranscriptionLanguage protocol メソッドに揃える（#82 コメント参照）
- ProcessingCoordinator（#85）に diarization ジョブ（#77 系）を接続
- KeychainService に APIKeyProviding 適合宣言 + DeepLTranslationProvider へ注入（#95 コメント参照）
- 字幕トグルの表示条件を translationEnabled（#93）に差し替え + LiveTranscriptView の2レーン化結線（#92 コメント参照）
- TranslationCoordinator の appleProvider/makeBYO プレースホルダを実 provider（#80/#79/#86）に差し替え
- SettingsView / RecordingView / SegmentListView の複数 PR 間の小コンフリクト解消
- スナップショット PNG の実機再記録（サンドボックス描画差のため）

## ユーザー実機検証チェックリスト（優先順）

1. **TASK-11/TCC（最重要）**: 無署名ビルドでシステム音声の TCC prompt が発火するか。PR #71 で「無署名ビルドには entitlements が埋め込まれない」ことが実証済みのため発火しない可能性が高い → その場合 Developer ID Program 取得判断へ
2. **TASK-18 PoC（#80 のマージ前提条件）**: .translationTask 常駐 drain の成立 / 0pt ホストからのモデル DL 同意 UI / ja↔en 実翻訳
3. TASK-41: 日本語固定→日本語認識 / TASK-14: streaming 品質・レイテンシ / TASK-12: 2系統同時録音の2ファイル生成
4. TASK-24/25: 実音声 diarize + FluidAudio モデル初回 DL / TASK-27: 類似度分布→閾値0.82 判断 / TASK-31: DER 実測（docs/diarization-benchmark.md）
5. TASK-19: 画面共有への非映り込み / TASK-15: Zoom/Teams/Meet 検出 / TASK-34: 実 mp3/mp4 取り込み / TASK-42: dmg 実配布・Gatekeeper 確認
6. UI 目視: TASK-30/29/36/13/32/33 の見た目（RenderPreview / 実機）

## 完了時の同期ルール（各 PR マージ後）

backlog タスクを Done 化 + finalSummary 記入 + `gh issue close <n> --comment "実装完了: <概要>"`。各タスクの対応 Issue 番号と手順はタスクコメントに記録済み。

## 依存関係マップ（参考・全タスク実装済みのため履歴）

旧版の依存マップはすべて消化済み。TASK-43 のみ全 PR マージ後に着手する。
