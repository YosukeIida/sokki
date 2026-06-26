# SuperIntern → sokki 機能取り込みプラン

## 背景

SuperIntern（https://super-intern.com）は「リアルタイム翻訳 + AI Canvas 議事録 + 会議後チャット」を提供する macOS 専用会議支援アプリ。sokki はこのうち **リアルタイム翻訳を中核機能として取り込む**（FR-TRANS-1〜6）。一方、**要約・アクション抽出・会議後チャット（AI Canvas 系）は当面スコープ外**とし、将来の任意機能（Phase 6）として位置づける。

**当面の取り込み方針（ユーザー確定）**:
- リアルタイム翻訳: 既定は Apple Translation（オンデバイス・無料）、BYO key で Gemini Live Translate / Google Cloud Translation v3 / DeepL を選択可能。
- 完全ローカルは「選択可能なプライバシーモード（既定 ON）」に格下げ。翻訳など任意機能は明示オプトインでクラウド利用。
- 要約・アクション抽出・会議後チャットは実装しない（将来検討）。

---

## Gemini Live Translate API 仕様

SuperIntern が採用していると推定される API（**確証なし・推定確率 60–70%**。公開情報に MT エンジンの記載はない）。**2026-06 時点でパブリックプレビュー**であり、約 $2.2/時とコストが高い（他 MT API の 7 倍以上）。本番採用は慎重に行い、BYO key の「実験的」オプションとして提供する。字幕のみ必要な場合は `inputAudioTranscription`/`outputAudioTranscription` でテキスト取得できる。

| 項目 | 仕様 |
|---|---|
| **モデルID** | `gemini-3.5-live-translate-preview` |
| **プロトコル** | WebSocket (WSS) — ステートフル双方向 |
| **音声入力** | Raw 16-bit PCM, **16kHz**, mono, little-endian |
| **音声出力** | Raw 16-bit PCM, 24kHz, mono, little-endian |
| **推奨チャンクサイズ** | 100ms |
| **対応言語** | 70言語以上（日本語・英語・中国語・韓国語含む）|
| **Swift SDK** | なし → `URLSessionWebSocketTask` で直接接続 |
| **価格** | Input: ~$0.0053/分、Output: ~$0.018/分（約 $0.32/時間）|

### sokki との音声フォーマット互換性
sokki の既存パイプラインは **16kHz mono Float32 PCM** → Gemini の要求する **16kHz mono Int16 PCM** とサンプルレートが一致。Float32 → Int16 変換を挟むだけで接続可能。

---

## 提案アーキテクチャ: ハイブリッド（ローカル + API）

```
音声キャプチャ（AVAudioEngine Phase1 / SCStream Phase2）
            ↓
  ┌─────────┴──────────┐
  │ローカル処理          │クラウド処理（オプション）
  │                     │
  │ WhisperKit          │ Gemini Live Translate
  │ → 日本語文字起こし   │ → リアルタイム翻訳字幕
  │ （高精度・オフライン）│ （70言語・高品質）
  │                     │
  │ SpeakerKit          │
  │ → 話者分離          │
  │                     │
  │ SpeakerProfileStore │
  │ → 声紋永続記憶      │
  └─────────┬──────────┘
            ↓
    リアルタイム翻訳（TranslationProvider）
    Apple Translation（既定・オンデバイス）/ Gemini Live Translate 等（BYO key）
    → リアルタイム翻訳字幕

    ── 以下は当面スコープ外（Phase 6・任意） ──
    LLM連携: Gemini Flash API / ローカルLLM（Ollama）
    → 会議後サマリー・アクション抽出・チャット
```

### ローカル vs API の役割分担

| 機能 | 担当 | 理由 |
|---|---|---|
| 日本語文字起こし精度 | **ローカル（WhisperKit）** | sokki の核心差別化。精度・プライバシー優位 |
| 話者分離 | **ローカル（FluidAudio）** | embedding 取得が確実、オンデバイス完結 |
| 声紋永続記憶 | **ローカル（SpeakerProfileStore）** | SuperIntern にない差別化機能 |
| リアルタイム翻訳 | **Apple Translation（既定）/ Gemini Live Translate 等（BYO key）** | `TranslationProvider` で切替。既定はオンデバイス、必要時にクラウド |
| 会議後サマリー | ~~Gemini Flash / ローカルLLM~~ | **当面スコープ外（Phase 6・任意）** |
| アクション抽出 | ~~同上~~ | **当面スコープ外（Phase 6・任意）** |
| 会議後チャット | ~~同上~~ | **当面スコープ外（Phase 6・任意）** |

---

## SuperIntern 機能 × sokki 実現可能性

| SuperIntern 機能 | 実現 | 方法 |
|---|---|---|
| ボットレス音声キャプチャ | 🟡 マイクのみ実装済み | システム音声は Core Audio Taps（推奨）/ SCStream を Phase 2 で配線 |
| 話者識別（diarization） | 🟡 型のみ（未配線） | **FluidAudio**（Phase 3）。SpeakerKitEngine は現状 `embedding: nil` |
| 声紋永続記憶 | 🟡 設計済み・未配線 | SpeakerProfileStore（FluidAudio `extractEmbedding()` で実証） |
| リアルタイム翻訳 | ⬜ 未着手（新規 Phase 2.5） | Apple Translation（既定）/ Gemini Live Translate 等（BYO key） |
| 会議後サマリー生成 | ⬜ **当面スコープ外** | Phase 6・任意 |
| アクション項目自動抽出 | ⬜ **当面スコープ外** | Phase 6・任意 |
| 会議後チャット（Q&A） | ⬜ **当面スコープ外** | Phase 6・任意 |
| テンプレートシステム | ✅ 実現可能 | AppSettingsModel 拡張 |
| カスタム辞書 | ✅ 実現可能 | Whisper の initial_prompt に注入 |
| 会議ツール自動検出 | ⚠️ 限定的 | 前面アプリ名取得は可能 |

---

## UI/UX 採用判断

### 採用する UI パターン

1. **会議中フローティング翻訳字幕** ← SuperIntern の核心 UX
   - SCStream 完了後（Phase2）、会議ウィンドウ横にオーバーレイ表示
   - Gemini Live Translate の文字起こし + 翻訳を2レーンで表示

2. **会議後の AI タブ（3ペイン）**
   - サマリー / アクション項目 / チャット
   - `SessionDetailView` に「AI」タブを追加

3. **録音開始前のテンプレート選択**
   - `RecordingView` にポップオーバーで追加（「定例会議」「インタビュー」「講義」等）

### sokki 独自の UI（SuperIntern にない）
- **声紋プロファイルカード** — セッション横断で同一話者を可視化
- **ローカル / API モードインジケーター** — プライバシー状態を明示
- **翻訳 ON/OFF トグル** — API コスト意識のあるユーザー向け

### 完全採用は不推奨
SuperIntern の UX は「翻訳中心」設計。sokki の差別化（声紋永続記憶・日本語精度）が埋もれるリスクあり。**部分参考 + 独自設計**を推奨。

---

## 実装ロードマップ

```
Phase 2: SCStream + リアルタイムストリーミング
  ↑ここで Gemini Live Translate 統合を追加
    GeminiLiveTranslateClient.swift（新規）
    AudioConverter.swift（Float32→Int16 変換）
    LiveTranscriptView に翻訳レーン追加

Phase 3: SpeakerKit 話者分離 + 声紋永続化（変更なし）

Phase 4: エクスポート拡充（変更なし）

Phase 5（拡張）: AI 機能 = SuperIntern 機能群
  - 会議後サマリー（Gemini Flash API）
  - アクション項目抽出
  - 会議後チャット
  - テンプレートシステム
  - SettingsView に API キー設定追加
  - プライバシーモード切り替え（ローカル完結 ON/OFF）
```

---

## 主要実装ファイル

| 新規/変更 | ファイル | 内容 |
|---|---|---|
| 新規 | `Sources/SokkiKit/Translation/TranslationProvider.swift` | protocol（`isOnDevice` 含む） |
| 新規 | `Sources/SokkiKit/Translation/AppleTranslationProvider.swift` | オンデバイス既定実装 |
| 新規 | `Sources/SokkiKit/Translation/GeminiLiveTranslateClient.swift` | WebSocket クライアント（BYO key） |
| 新規 | `Sources/SokkiKit/Translation/PCMConverter.swift` | Float32→Int16 変換 |
| 変更 | `Sources/SokkiKit/Audio/AudioCaptureManager.swift` | Core Audio Taps（ProcessTap）配線 |
| 変更 | `Sources/SokkiKit/Diarization/SpeakerKitEngine.swift` →（追加）`FluidAudioEngine.swift` | embedding 取得・SpeakerProfileStore 配線 |
| 変更 | `Sources/SokkiKit/UI/RecordingView.swift` | 翻訳字幕 2 レーン + プライバシーインジケーター + 翻訳トグル |
| 変更 | `Sources/SokkiKit/Models/AppSettingsModel.swift` | キャプチャ方式・プライバシー・翻訳設定追加 |
| 変更 | `Sources/SokkiKit/UI/SettingsView.swift` | プロバイダ/言語/API キー設定 UI |

---

## コスト試算

> **価格前提の注記**: 本表は当初の楽観値（約 $0.32/時）に基づく。翻訳調査の実測では Gemini Live Translate は入出力合計で **約 $2.2/時**（25 tokens/秒換算）であり、コストは下表の約 7 倍になる可能性がある。コストを抑えたい場合は **Apple Translation（オンデバイス・無料）を既定**とし、Google Cloud Translation v3（$20/100万文字）や DeepL（$5.49/100万文字）も選択肢に含める。

| 利用パターン | 楽観値（$0.32/時） | 実測ベース（~$2.2/時） |
|---|---|---|
| 会議 3回/週 × 2時間 | ~$7.68/月 | ~$52.8/月 |
| 会議 5回/週 × 1時間 | ~$6.40/月 | ~$44.0/月 |
| 講義録音 20時間/月 | ~$7.04/月 | ~$44.0/月 |

いずれの場合も **BYO API Key（ユーザーが自分の API キーを設定）モデル**を採用し、アプリは課金しない。Apple Translation 既定により「無料で使い始められる」体験を確保する。

---

## sokki の差別化ポイント（SuperIntern との比較）

| 機能 | sokki | SuperIntern |
|---|---|---|
| 完全オフライン処理 | ✅ 設定可（プライバシーモード）| ❌ クラウド依存 |
| 声紋永続記憶（セッション横断）| ✅ | ❌ |
| 日本語特化高精度文字起こし | ✅ WhisperKit | △ 汎用モデル |
| リアルタイム翻訳 | ✅ Gemini Live API | ✅ |
| 月額不要（BYO API Key）| ✅ | ❌ $20/月 |

---

## 参考リンク

- [Gemini Live API overview](https://ai.google.dev/gemini-api/docs/live-api)
- [Live translation with Gemini Live API](https://ai.google.dev/gemini-api/docs/live-api/live-translate)
- [Gemini 3.5 Live Translate announcement](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-live-3-5-translate/)
- [SuperIntern](https://super-intern.com/en)
