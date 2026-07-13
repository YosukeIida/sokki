# sokki ロードマップ（設計スナップショット）

> 作成: 2026-06-26 / **2026-07-12 更新: タスクの正本は Backlog.md（`backlog/`）へ移行**。本ファイルはフェーズ構成・依存関係・設計根拠のスナップショットとして保持する（タスク状態はここでは更新しない）。GitHub Issues は backlog の同期ミラー（同期ルールは CLAUDE.md 参照）。
> （経緯）作成時点では本ファイルが正本で、旧 GitHub Issue（#1〜#22）を全クローズして #23〜#57 を作り直した。
> 方針: API ハイブリッド化（[[project-sokki-direction]] / requirements.md / spec.md 改訂済み）。要約系は当面スコープ外（Phase 6）。
> 根拠: `docs/implementation-feasibility.md` §6 の推奨ロードマップ＋ユーザー確定事項。

## 確定した設計判断（このロードマップの前提）

- **システム音声 = Core Audio Taps（ProcessTap）を既定**、SCStream は代替（spec D-1 改訂 / D-9 / D-10）。
- **データ永続化 = SwiftData を維持**（Core Data へは戻さない / D-4）。
- **翻訳 = 2 段構え**。既定 Apple Translation（オンデバイス・無料）→ BYO key で Gemini Live Translate / Google Cloud v3 に切替（`TranslationProvider` 抽象 / D-12）。DeepL は D-18 で撤去済み。詳細設計は `docs/translation-architecture.md`。
- **話者分離 = FluidAudio を主候補**。ただし `DiarizationEngine` protocol で**後から差し替え可能な柔軟実装**を維持（D-5 / D-11）。エンジン選定は実測後に変更しうる。
- **要約・アクション抽出・会議後チャット = 当面スコープ外**（Phase 6・任意）。
- **増分実装**（既存の protocol/actor/DI 抽象の上に積む。フルスクラッチ書き換えはしない）。

## ラベル体系

`Phase1` / `Phase2` / `Phase2.5` / `Phase3` / `Phase4` / `Phase5` / `Phase6` / `design` / `bug` / `test` / `infra`

> タスク ID（P1-1 等）は本 md 内の安定参照用。GitHub の Issue 番号は作成時に自動採番される。

---

## Phase 1 — MVP 仕上げ（最優先・残作業）

> 現状: マイク録音→WhisperKit バッチ→SwiftData 保存→Markdown コピー まで動作。テスト 20 件緑。
> **重大ギャップ**: 録音音声をディスクに保存していない（`AVAudioFile` 呼び出し 0 件）。再生・再処理の前提が欠落。

| ID | タイトル | 完了基準 | 依存 |
|---|---|---|---|
| **P1-1** | 録音音声をディスクへ保存（.m4a / .wav） | `AudioCaptureManager` に AVAudioFile writer を追加し、マイク録音を実ファイル化。`SessionModel.audioFilePath` が実体を指す。停止後にファイルが存在することをテスト | — |
| **P1-2** | 録音停止後に `durationSeconds` を更新 | stop 時に `SessionManager.updateDuration` を呼ぶ（API は既存）。一覧・詳細に正しい長さが出る | P1-1 |
| **P1-3** | 録音一覧・詳細画面の E2E 動作確認 | Xcode ⌘R でマイク録音→文字起こし→一覧→詳細→セグメント表示まで通し確認 | P1-1 |
| **P1-4** | Markdown エクスポートの動作確認 | 話者名・タイムスタンプ付き Markdown がクリップボード/ファイルに出る（ExportTests は通過済み、実機確認） | P1-3 |
| **P1-5** | エクスポートにファイル保存ダイアログ + Security-Scoped Bookmark | クリップボードだけでなく保存先選択に対応。Sandbox 下で再アクセス可能 | P1-4 |
| **P1-6** `design` | claude.ai/design で各画面のデザイン先行作成 | 録音 / 一覧 / 詳細 / 話者プロファイル / 設定 のビジュアル確定、ハンドオフバンドル取得 | — |

---

## Phase 2 — システム音声（Core Audio Taps）+ リアルタイム

| ID | タイトル | 完了基準 | 依存 |
|---|---|---|---|
| **P2-0** `infra` | 配布方針の意思決定（ブロッカー） | Core Audio Taps と署名/配布（NFR-5 コード署名なし）が両立するか検証し、Developer ID 署名 or App Store or 署名なしを確定。Open Question を 1 つ閉じる | — |
| **P2-1** | システム音声キャプチャ（Core Audio Taps / ProcessTap） | `AudioCaptureManager` に `ProcessTap` を内包し `systemStream` / `systemLevelStream` を配線。`startCapture(.systemOnly)` の throw を解除。参照: `docs/recap-codebase-analysis.md` §0+本文（WhisperKit/entitlement の訂正に注意） | P2-0 |
| **P2-2** | Both モード（マイク + システム同時） | 起動順: system（tap）先 → `tapStreamDescription` 確定 → mic を targetFormat で起動（停止は逆順）。2 ファイル別保存 | P2-1, P1-1 |
| **P2-3** | レベルメーター UI 配線 | `LevelMeterView` / `WaveformView` に mic=青 / system=赤 の実レベルを供給（system は dBFS ピーク、mic も dBFS に統一） | P2-1 |
| **P2-4** | リアルタイムストリーミング文字起こし | WhisperKit v1.0 の streaming/確定境界 API を実機確認し、現状の擬似窓実装を置換 or 確定境界を実装。Hypothesis（灰）/ Confirmed（黒）2 系統表示。参照: WhisperAX サンプル | P2-1 |
| **P2-5** | 会議自動検出（任意・前倒し可） | `SCShareableContent`（画面収録権限不要）+ bundleID + タイトルパターンで Zoom/Teams/Meet 検出→録音提案。参照: `recap-codebase-analysis.md` 会議検出章。要約非依存で安全に追加可 | — |
| **P2-6** | 録音後処理オーケストレーション | `ProcessingCoordinator`（AsyncStream 直列キュー）で 停止→文字起こし→（話者分離）→保存 を体系化。スリープ復帰・キャンセル対応。**要約フェーズは省略**（Recap の completeProcessingWithoutSummary 相当） | P2-4 |

---

## Phase 2.5 — リアルタイム翻訳（新規・2 段構え）

> 詳細設計: `docs/translation-architecture.md`（`TranslationProvider` 抽象 + 2 段ルーティング + プライバシーゲート）。

| ID | タイトル | 完了基準 | 依存 |
|---|---|---|---|
| **P25-1** | `TranslationProvider` protocol + ルーティング層 | protocol（`isOnDevice` / `supports(source:target:)` / `translateStream`）と `TranslationCoordinator`（Tier1 Apple → Tier2 BYO の自動ルーティング + プライバシーゲート）を実装 | — |
| **P25-2** | `AppleTranslationProvider`（既定・オンデバイス） | macOS 15 Translation Framework で確定セグメントを翻訳。`.translationTask` 制約に対応した供給経路。19 言語、モデル DL プロンプト対応 | P25-1 |
| **P25-3** | 翻訳字幕 UI（2 レーン + フローティング） | 録音中に原文/訳文の 2 レーン表示。会議横のフローティングオーバーレイ（`NSPanel`, `sharingType=.none` で画面共有非映り込み） | P25-2, P2-4 |
| **P25-4** | 翻訳 ON/OFF トグル + プロバイダ/言語選択 | `SettingsView` と録音画面トグル。OFF 時はクラウド送信ゼロ。プライバシーモード時は `isOnDevice==false` を抑止 | P25-1 |
| **P25-5** | `GeminiLiveTranslateClient`（BYO key・実験的） | `URLSessionWebSocketTask` + `PCMConverter`（Float32→Int16）。字幕は input/outputAudioTranscription から取得。プレビュー扱いの注意表示 | P25-1 |
| **P25-6** | BYO REST プロバイダ（Google Cloud v3） | Google Cloud v3 は OAuth2/サービスアカウントが必要（生 API キー不可）のため実装優先度は後続。参照: `translation-architecture.md` §0-8。**D-18 で DeepL は撤去済み。クラウド BYO は Gemini Live のみ**（当初 DeepL を「REST + 単純キーで実装容易」として優先していたが、オンデバイス優先 + LLM ベースの方向性へ回帰） | P25-1 |
| **P25-7** | API キーを Keychain で管理 | `translationApiKey` を AppSettings 平文から Keychain へ移行。参照: Recap `KeychainService` | P25-4 |

---

## Phase 3 — 話者分離 + 声紋永続化（差別化の本丸）

> `DiarizationEngine` protocol で**後から差し替え可能**な柔軟実装を維持（エンジンは実測後に変更しうる）。

| ID | タイトル | 完了基準 | 依存 |
|---|---|---|---|
| **P3-1** | 話者分離エンジン統合（FluidAudio 主候補 / SpeakerKit 代替） | `DiarizationEngine` 準拠の `FluidAudioEngine` を追加し、`diarize` が実データの `DiarizationSegment` を返す。SpeakerKit と protocol レベルで交換可能 | — |
| **P3-2** | embedding 取得 → SpeakerProfileStore 配線（現状 `embedding: nil` の解消） | diarization が 256dim L2 正規化 embedding を返し、`SpeakerProfileStore` が実働（findOrCreate / EMA 更新）。空回りを解消 | P3-1 |
| **P3-3** | WhisperKit セグメントと diarization のマージ | 時間軸アラインメントで各文字起こしセグメントに speakerLabel を付与（参照: WhisperX、~30 行） | P3-1, P2-4 |
| **P3-4** | 声紋照合（EmbeddingMatcher） | 実装済み・テスト通過。実 embedding で閾値 0.82 を検証 | P3-2 |
| **P3-5** | 話者プロファイル永続化（EMA） | セッション横断で同一話者を認識。`SpeakerProfileModel` 更新 | P3-2 |
| **P3-6** | 話者カラーバー付き SessionDetailView | 詳細画面の左端に話者カラー、話者ごと色分け | P3-3 |
| **P3-7** | SpeakerProfileView UI | プロファイル一覧・名前編集・出現回数・削除 | P3-5 |
| **P3-8** `test` | 日本語 DER・声紋閾値の実測 | 日本語音声で DER と閾値 0.82 の妥当性を計測（参考: Sortformer 12.7% / Pyannote 28.8%）。Open Question を閉じる | P3-3 |

---

## Phase 4 — エクスポート拡充・音声再生・エンジン追加

| ID | タイトル | 完了基準 | 依存 |
|---|---|---|---|
| **P4-1** | SRT / VTT エクスポート確認 | 実装済み（先取り）。実セッションで出力確認 + ファイル保存 UI | P1-5 |
| **P4-2** | `AudioPlaybackController` 新規 + セグメント同期再生 | セグメントクリックで該当時刻から再生（FR-DATA-3）。保存音声が前提 | P1-1 |
| **P4-3** | ファイルインポート（.mp4/.m4a/.wav/.mp3） | `AudioFileImporter` を実装し、既存ファイルを文字起こし・話者分離 | P3-3 |
| **P4-4** | Apple SpeechAnalyzer エンジン（macOS 26+） | `TranscriptionEngine` 準拠でドロップイン評価（参照: swift-scribe） | P2-4 |

---

## Phase 5 — 配布・プライバシー

| ID | タイトル | 完了基準 | 依存 |
|---|---|---|---|
| **P5-1** | プライバシーモード切替 UI + ローカル/API インジケーター | 既定 ON。状態を録音画面に明示。`isOnDevice==false` プロバイダの抑止と連動 | P25-4 |
| **P5-2** `infra` | Homebrew Cask 配布 + Gatekeeper 回避ドキュメント | `brew install --cask sokki` で導入可。署名方針（P2-0）と整合 | P2-0 |

---

## Phase 6 — LLM 後処理（任意・将来 / 当面スコープ外）

> 着手しない。将来検討時に `gh issue list --label "Phase6"` で管理。

- 会議後サマリー / アクション抽出 / 会議後チャット（OpenAI 互換 / Gemini Flash、BYO key）
- LLM 話者名推定（`OpenAICompatClient` + `SpeakerNamingService`）

---

## GitHub への反映手順（実行は別途確認のうえ）

```bash
# 1) 既存 Issue を全クローズ（塗り替え）
gh issue list --state open --json number -q '.[].number' | xargs -I{} gh issue close {} --comment "ロードマップ刷新により再作成（docs/roadmap.md）"

# 2) ラベル整備
gh label create Phase2.5 --color FBCA04 2>/dev/null; gh label create Phase6 --color EEEEEE 2>/dev/null; gh label create infra --color 0E8A16 2>/dev/null

# 3) 本 md の各タスクを gh issue create で作成（Phase ラベル付与）
```
