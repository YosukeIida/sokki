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

## 現在地（2026-07-14 codex-pr-review + 段階マージ完了後）

- **マージ済み（27/29）**: Stage 0〜5 で #67〜#95 のうち #80/#92 を除く全 PR を codex-pr-review（3層体制）で再レビュー・修正のうえ main へマージ。main = 348 テスト全 PASS（Snapshot 含む）
- **マージ保留（2本）**: **#80**（TASK-18 AppleTranslation）= Coordinator への DI 結線（統合タスク）→ 実機 PoC 成功が前提。**#92**（TASK-19 字幕UI）= #80 の後
- **残タスク**: Stage 6 = 統合タスク（下記）+ フォローアップ（TASK-44〜57、**TASK-44 採番衝突は high**）→ TASK-43（デザイントークン適用）。TASK-37（Homebrew Cask）= Developer ID 取得まで保留
- レビュー成果: 実バグ修正多数（末尾40ms欠落・負のDER confusion・廃止Geminiモデル・世代奪還レース等）。各 PR の詳細は PR コメントと backlog finalSummary 参照

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
5. TASK-19: 画面共有への非映り込み（**PR #92 レビューで判明: sharingType=.none は macOS 15+ の ScreenCaptureKit 経路では無視される（既知の回避策なし）**。Zoom/QuickTime が SCK 経由か実機確認し、映り込む場合は共有中に自動で隠すフォールバック UX を検討） / TASK-15: Zoom/Teams/Meet 検出（会議検出 ON 時に画面収録 TCC prompt が発火するか + 権限拒否時に無言で動かない挙動の確認 — PR #74 レビュー指摘 → 権限 UI は TASK-46） / TASK-34: 実 mp3/mp4 取り込み / TASK-42: dmg 実配布・Gatekeeper 確認 / TASK-23: 無署名/ad-hoc 配布ビルドで Keychain ACL が再ビルド・再配布をまたいで継続するか（PR #95 レビュー指摘。拒否時は SettingsView がキーチェーンアクセス App への誘導を表示する）
6. UI 目視: TASK-30/29/36/13/32/33 の見た目（RenderPreview / 実機）

## 完了時の同期ルール（各 PR マージ後）

backlog タスクを Done 化 + finalSummary 記入 + `gh issue close <n> --comment "実装完了: <概要>"`。各タスクの対応 Issue 番号と手順はタスクコメントに記録済み。

## 依存関係マップ（参考・全タスク実装済みのため履歴）

旧版の依存マップはすべて消化済み。TASK-43 のみ全 PR マージ後に着手する。
