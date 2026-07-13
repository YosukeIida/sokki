# 要件定義書 — sokki（速記）

> 作成日: 2026-03-28
> 更新日: 2026-05-27
> ステータス: Draft v0.2
> 対象OS: macOS 15+ (Apple Silicon)

---

## 1. 概要

会議・講義・インタビュー・独り言など、多様な音声シーンに対応する macOS ネイティブの音声文字起こしアプリ。

**三本柱**: 日本語高精度オンデバイス文字起こし / 声紋を記憶する話者分離 / リアルタイム翻訳（API ハイブリッド）

**ローカル完結は「既定 ON のプライバシーモード」として選択可能にする**（従来の絶対条件から格下げ）。文字起こし・話者分離・声紋永続記憶はオンデバイスで完結する一方、リアルタイム翻訳や任意の後処理はユーザーが自分の API キー（BYO key）でクラウドを利用できる。

既存ツール（MacWhisper Pro、WhisperMate、Granola、SuperIntern）に対し「日本語 diarization × 声紋永続記憶 × ローカル/API ハイブリッド × Homebrew 配布」の同時実現を目標とする。

---

## 2. ユースケース

| # | シーン | 主な特性 |
|---|--------|----------|
| UC-1 | 会議・ミーティング | 複数話者 / リアルタイム字幕 / 後からサマリー |
| UC-2 | 講義・授業 | 長時間録音 (1–2h) / 単一話者 or 2–3名 |
| UC-3 | インタビュー | 話者分離が特に有効 / バッチ処理でOK |
| UC-4 | 独り言・メモ | 単一話者 / 軽量 / 即時テキスト化 |

---

## 3. 機能要件

### 3.1 音声キャプチャ

- **FR-CAP-1** マイク入力（AirPods Pro 含む）をキャプチャできること
- **FR-CAP-2** システム音声（Zoom / Meet / Teams などの相手の声）をキャプチャできること
  - 実装は次の 2 方式から選択可能（設計判断 D-1 / D-10 参照）:
    - **方式 A: Core Audio Taps（`CATapDescription` + Aggregate Device、Recap 流 `ProcessTap`）** — 画面収録権限不要、プロセス単位タップ、Recap が MIT で参照実装を提供（推奨・既定）
    - **方式 B: `ScreenCaptureKit`（単一 SCStream、`SCStreamOutputType` でレーン分岐）** — 画面収録権限が必要、macOS 15 以降で `captureMicrophone = true` が利用可能
- **FR-CAP-3** マイク＋システム音声を同時キャプチャできること
  - 起動順序: システム（tap）を先に起動し `tapStreamDescription` を確定 → その `targetFormat` でマイクを起動（停止は逆順）
- **FR-CAP-4** 既存の動画・音声ファイル（.mp4, .m4a, .wav, .mp3）を読み込めること
- **FR-CAP-5** 録音 UI でマイク / システム / Both を切り替えて波形を分離表示できること
  - マイク = 青（#3B82F6）、システム = 赤（#EF4444）

### 3.2 文字起こしエンジン

- **FR-ASR-1** リアルタイム文字起こし（録音しながら字幕表示）に対応すること
- **FR-ASR-2** バッチ文字起こし（録音ファイルを後処理）に対応すること
- **FR-ASR-3** 日本語に対応すること（精度優先）
- **FR-ASR-4** 文字起こしエンジンを切り替えられること（§5 参照）
- **FR-ASR-5** エンジンは `TranscriptionEngine` プロトコルで抽象化し、追加・交換を容易にすること

### 3.3 話者分離 + 声紋永続化

- **FR-DIA-1** 話者分離（誰がいつ話したか）を**オンデバイスで**オプション実行できること（クラウド送信しない、プライバシーモードでも常に利用可）
  - 実装は `DiarizationEngine` protocol で抽象化し、次のエンジンを切替可能にする:
    - `SpeakerKit`（Pyannote v4 Core ML、統合が最も容易。ただし embedding 取り出し API は v1.0 時点で未確認 — 未決定事項参照）
    - **`FluidAudio`（推奨: `extractEmbedding()` が public で 256 次元 L2 正規化済み、`SpeakerProfileStore` 設計と完全一致。日本語 DER も Sortformer 採用で大幅改善）**
- **FR-DIA-2** 話者ラベルを文字起こしセグメントに付与できること（`Speaker_00` 等）
- **FR-DIA-3** 声紋ベクトル（256 次元）を SwiftData に永続化し、次回セッションでも同じ話者を認識できること（**sokki 最大の差別化機能。オンデバイス完結**）
  - コサイン類似度（vDSP）で照合、閾値 0.82（設定変更可）
  - 指数移動平均（alpha=0.1）でセッションごとにプロファイルを更新
  - 前提: diarization エンジンが embedding を返すこと（`DiarizationSegment.embedding`）。現状 `SpeakerKitEngine` は `embedding: nil` のため、本機能の実証は FluidAudio `extractEmbedding()` で行う
- **FR-DIA-4** 話者の表示名をユーザーが編集できること（"田中さん" 等）
- **FR-DIA-5** LLM を用いた話者名の自動推定をオプションで実行できること
  - 実装: OpenAI 互換エンドポイントへの HTTP 呼び出し（Ollama / Claude API 等）

### 3.4 データ管理

- **FR-DATA-1** セッション単位でデータを管理できること
- **FR-DATA-2** 各セッションは以下のデータを保持すること

```
SessionModel
├── id: UUID
├── title: String           // 例: "Meeting_20260527"
├── createdAt: Date
├── audioFilePath: String   // URL.path
├── durationSeconds: Double
├── captureMode: String     // "mic" | "system" | "both" | "file"
└── segments: [SegmentModel]
      ├── id: UUID
      ├── start: Double         // 秒
      ├── end: Double
      ├── text: String
      ├── avgLogProb: Float
      ├── speakerLabel: String? // "SPEAKER_00"
      └── speakerProfile: SpeakerProfileModel?

SpeakerProfileModel
├── id: UUID
├── displayName: String     // ユーザー編集可
├── embeddingData: Data     // [Float] 256dim × 4 bytes = 1024 bytes
├── embeddingCount: Int     // EMA 重み管理
├── createdAt: Date
├── lastSeenAt: Date
└── colorHex: String        // 話者カラー
```

- **FR-DATA-3** セグメントをクリックするとその時刻の音声を再生できること

### 3.5 エクスポート

| 形式 | 用途 | 備考 |
|------|------|------|
| Markdown | Obsidian 連携 / 全文コピー | 話者名・タイムスタンプ付き |
| SRT | 動画字幕ファイル | 標準字幕フォーマット |
| VTT | Web 動画字幕 | HTML5 video 対応 |
| プレーンテキスト | 最小出力 | 話者・時刻なし |

- **FR-EXP-1** Markdown エクスポートは以下のフォーマットで出力すること

```markdown
## Meeting_20260527

**田中さん** `00:00:00`
こんにちは、はじめまして。

**佐藤さん** `00:00:07`
後の成功の基盤となります...
```

---

### 3.6 リアルタイム翻訳（同時通訳）

- **FR-TRANS-1** 文字起こし結果をリアルタイムに別言語へ翻訳し、字幕として表示できること（録音中フローティング字幕 + セッション内 2 レーン表示）
- **FR-TRANS-2** 翻訳エンジンを `TranslationProvider` protocol で抽象化し、追加・交換を容易にすること
- **FR-TRANS-3** 翻訳プロバイダを設定で切替可能にすること:
  - **Apple Translation Framework（既定）** — オンデバイス・無料・ネットワーク不要。19 言語。プライバシーモードでも利用可。字幕用途に最適
  - **Gemini Live Translate（BYO key, オプション）** — WebSocket、16kHz mono Int16 PCM、70 言語超。2026-06 時点でパブリックプレビュー・約 $2.2/時とコスト高のため「実験的」扱い
  - **Google Cloud Translation API v3 NMT（BYO key, オプション）** — REST、135+ 言語、$20/100万文字。partial transcript 確定ごとに HTTP 呼び出し（往復 50–150ms）
- **FR-TRANS-4** API キーはユーザーが設定（BYO key モデル）。アプリは API キーを保持・課金しない
- **FR-TRANS-5** 翻訳の ON/OFF をトグルで切替可能にすること（API コスト・プライバシー意識のため）。OFF 時は一切のクラウド送信を行わない
- **FR-TRANS-6** ソース言語・ターゲット言語をユーザーが選択できること（Apple Translation は事前モデルダウンロードに対応）

> 注: Google Cloud **Media Translation API** は 2024-07-01 にサービス終了済みのため採用しない。

---

## 4. 非機能要件

- **NFR-1** **プライバシーモード（既定 ON）** では音声データ・文字起こし結果をクラウド送信しないこと。プライバシーモードはローカル完結を保証する選択可能なモードであり、文字起こし・話者分離・声紋永続記憶は常にオンデバイスで完結する。リアルタイム翻訳や任意の後処理を使う場合のみ、ユーザーの明示的なオプトイン（BYO key 設定 + 翻訳トグル ON）でクラウドへ送信する
- **NFR-2** Apple Silicon (M1 以降) で快適に動作すること
- **NFR-3** バックグラウンド推論は ANE (Apple Neural Engine) にオフロードすること
- **NFR-4** macOS 15 (Sequoia) 以降を対象とすること
- **NFR-5** GitHub Releases で dmg 配布できること。初期は無署名（Gatekeeper 回避手順を案内）。Developer ID Program 取得後は Developer ID 署名 + 公証に移行し、Homebrew Cask 配布（TASK-37）も検討する（TASK-10 決定・2026-07-13）
- **NFR-6** Xcode + Swift Package Manager で管理できること

---

## 5. 技術スタック

### エンジン構成

```swift
protocol TranscriptionEngine: Actor {
    func prepare() async throws
    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment]
    func transcribeStream(audioChunks: AsyncStream<AudioChunk>) -> AsyncThrowingStream<any TranscriptionSegment, Error>
}

protocol DiarizationEngine: Actor {
    func prepare() async throws
    func diarize(audioArray: [Float]) async throws -> DiarizationResult
}

protocol TranslationProvider: Actor {
    func prepare(source: Locale.Language, target: Locale.Language) async throws
    /// 確定/暫定セグメントを区別して返すストリーミング翻訳
    func translateStream(
        textChunks: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error>
    var isOnDevice: Bool { get }   // Apple Translation = true, クラウド = false
}
```

| エンジン | 優先度 | 状態 | 備考 |
|----------|--------|------|------|
| WhisperKit (large-v3-turbo) | Primary（文字起こし） | ✅ 利用可 | 日本語精度最優先、CER 約4-8%、オンデバイス |
| Apple SpeechAnalyzer | Secondary（文字起こし） | macOS 26+ | 速度最優先（34分→45秒）、追加 DL 不要 |
| FluidAudio | Primary（話者分離） | 要統合 | `extractEmbedding()` public・256dim L2 正規化済み |
| SpeakerKit | Secondary（話者分離） | 統合最易 | embedding 公開は v1.0 で未確認 |
| Apple Translation | Primary（翻訳） | macOS 15+ | オンデバイス・無料・19 言語 |
| Gemini Live Translate | Optional（翻訳, BYO key） | プレビュー | 70+ 言語・WebSocket・約 $2.2/時 |
| Google Cloud Translation v3 | Optional（翻訳, BYO key） | 安定版 | 135+ 言語・REST・$20/100万文字 |

### コンポーネント一覧

| レイヤー | 技術 | 役割 |
|----------|------|------|
| 音声キャプチャ | **Core Audio Taps（ProcessTap）** または ScreenCaptureKit（単一 SCStream） | マイク + システム音声同時取得、レーン分離（D-1 / D-10） |
| 文字起こし | WhisperKit v1.0 (`argmax-oss-swift`) | Core ML / ANE 最適化、日本語対応（オンデバイス） |
| 話者分離 | **FluidAudio（推奨）** / SpeakerKit (Pyannote v4 Core ML) | オンデバイス diarization + 声紋 embedding 取得 |
| 声紋永続化 | SwiftData + vDSP コサイン類似度 | セッション間話者認識の核心（オンデバイス） |
| **リアルタイム翻訳 (optional)** | **Apple Translation（既定・オンデバイス）/ Gemini Live Translate / Google Cloud Translation v3（BYO key）** | `TranslationProvider` で抽象化、字幕表示。DeepL は spec.md D-18 で撤去済み |
| データ永続化 | SwiftData (SQLite) | セッション管理 |
| UI | SwiftUI | macOS ネイティブ |
| 後処理 (optional, **将来**) | OpenAI 互換 / Gemini Flash エンドポイント | 要約・アクション抽出等は当面スコープ外（§7 参照） |

---

## 6. 配布・開発環境

- **アプリ名**: sokki（速記）
- **配布方法**: GitHub + Homebrew Cask (`brew install --cask sokki`)
- **ターゲットユーザー**: 開発者本人 + 機械学習理論研究室メンバー
- **リポジトリ**: GitHub (`YosukeIida/sokki`)
- **開発環境**: Xcode + xcodegen + Swift Package Manager

### ビルドシステム（2026-05-27 更新）

| ツール | 役割 |
|---|---|
| `xcodegen` + `project.yml` | `sokki.xcodeproj` を宣言的に生成・管理 |
| `Package.swift`（swift-tools-version: 6.0） | 外部依存（WhisperKit / SpeakerKit）の管理 |
| `swift build` / `swift test` | CLI によるビルド・テスト |
| Xcode MCP（`xcrun mcpbridge`） | Claude Code から `BuildProject` / `RenderPreview` を実行 |

### ターゲット構成

| ターゲット | 種別 | パス |
|---|---|---|
| `SokkiKit` | Library（Framework） | `Sources/SokkiKit/` |
| `sokki` | Executable（App） | `Sources/sokki/` |
| `sokkiTests` | Unit Test | `Tests/sokkiTests/` |

`SokkiKit` に全ビジネスロジック・UI コンポーネントを集約。
`ENABLE_DEBUG_DYLIB=YES` により `RenderPreview` / `ExecuteSnippet` が動作する。

---

## 7. 開発フェーズ

UI デザインは `claude.ai/design` で先行作成し、Claude Code ハンドオフバンドルから実装に反映する。

| フェーズ | 内容 | 状態 |
|----------|------|------|
| UI デザイン | 各画面の状態遷移・ビジュアル（claude.ai/design） | ⬜ 未着手 |
| Phase 1 (MVP) | マイク録音 + WhisperKit バッチ文字起こし + 音声ファイル保存(.m4a) + 最小 SwiftUI | 🔄 ほぼ完了（Issue #3-#5 残り。**音声ファイル未書き出しが Issue #4 の前提**） |
| Phase 2 | システム音声（Core Audio Taps）+ リアルタイムストリーミング + 波形 UI + 音声同期再生 | ⬜ 未着手 |
| Phase 2.5 | **リアルタイム翻訳（Apple Translation 既定 + BYO key プロバイダ）+ 翻訳字幕 UI** | ⬜ 未着手 |
| Phase 3 | 話者分離（FluidAudio）+ 声紋永続化 + SpeakerProfileView | ⬜ 未着手 |
| Phase 4 | Apple SpeechAnalyzer エンジン + SRT/VTT エクスポート + ファイルインポート | ⬜ 未着手 |
| Phase 5 | Homebrew Cask 配布 + プライバシーモード切替 UI | ⬜ 未着手 |
| Phase 6（任意・将来） | LLM 連携（要約・アクション抽出・会議後チャット） | ⬜ **当面スコープ外** |

### Phase 1 の実装状況（2026-05-27）

| 機能 | 状態 | 残作業 |
|---|---|---|
| マイクキャプチャ（AVAudioEngine） | ✅ 動作確認済み | — |
| WhisperKit バッチ文字起こし | ✅ 動作確認済み | — |
| 特殊トークン除去 | ✅ 修正済み | — |
| セッション保存（SwiftData） | ✅ 動作確認済み | durationSeconds 未更新 |
| セッション一覧・詳細表示 | ✅ 骨格実装済み | — |
| Markdown エクスポート | ✅ テスト通過済み | — |
| 音声ファイルのディスク保存 | ❌ 未実装 | .m4a 書き込みが必要 |
| 録音時間の記録 | ❌ 未実装 | durationSeconds 更新が必要 |

---

## 8. GitHub Issues 計画

### Phase 1 完成（最優先）
- `#1` WhisperKit 特殊トークン除去（✅ 修正済み）
- `#2` 録音一覧・詳細画面の E2E 動作確認
- `#3` 録音停止後に durationSeconds を更新
- `#4` 音声ファイルをディスクへ保存（.m4a）
- `#5` Markdown エクスポートの動作確認

### Phase 2
- `#6` レベルメーター UI
- `#7` システム音声キャプチャ（**Core Audio Taps（ProcessTap）を第一候補、SCStream を代替**）
- `#8` Both モード（マイク+システム同時、起動順序: system 先 → mic）
- `#9` リアルタイムストリーミング文字起こし
- `#10` 波形表示 UI
- `#11` セグメントクリックで音声再生

### Phase 2.5（新規: リアルタイム翻訳）
- `#22` `TranslationProvider` protocol + Apple Translation 実装（オンデバイス既定）
- `#23` 翻訳字幕 UI（録音中フローティング + 2 レーン表示）
- `#24` Gemini Live Translate クライアント（WebSocket, Float32→Int16 変換, BYO key）
- `#25` 翻訳 ON/OFF トグル + プロバイダ選択 + 言語選択（SettingsView）

### Phase 3
- `#12` 話者分離エンジン統合（**FluidAudio 推奨 / SpeakerKit 代替**）
- `#13` 声紋照合（EmbeddingMatcher — 実装済み・テスト通過）
- `#14` 話者プロファイル永続化（EMA）
- `#15` 話者カラーバー付き SessionDetailView
- `#16` SpeakerProfileView UI
- `#26` **diarization → SpeakerProfileStore 配線（現状 `embedding: nil` で空回りの解消）**

### Phase 4〜5
- `#17` SRT/VTT エクスポート確認
- `#18` Apple SpeechAnalyzer エンジン
- `#19` ファイルインポート
- `#20` LLM 話者名推定（任意・将来）
- `#21` Homebrew Cask 配布
- `#27` プライバシーモード切替 + ローカル/API インジケーター UI

### Phase 6（任意・将来 — 当面スコープ外）
- 要約 / アクション抽出 / 会議後チャット（`gh issue list --label "Phase6"`）

---

## 9. 未決定事項 (Open Questions)

- [x] ~~アプリ名~~ → **sokki**（速記）
- [x] ~~ビルドシステム~~ → xcodegen + SPM（xcodeproj 生成済み）
- [ ] claude.ai/design でのデザインシステム設定
- [x] ~~配布方針~~ → 初期は無署名 dmg 配布、Developer ID 取得後に署名+公証へ移行（TASK-10、2026-07-13）
- [ ] Homebrew Cask リポジトリの管理方法（個人 tap vs 公式）※ Developer ID 取得後に着手
- [ ] コード署名なし配布時の Gatekeeper 回避方法のドキュメント化（当面必要・優先度高）
- [ ] 話者分離の日本語 DER 実測（参考: Pyannote OSS community-1=28.8% / Sortformer v2=12.7% / DiariZen=15.6%、arXiv 2509.26177）※計測ハーネス整備済み（`docs/diarization-benchmark.md` / TASK-31）・実測待ち
- [ ] SpeakerKit v1.0 で embedding 取り出し API が公開されているかの確認（未公開なら FluidAudio `extractEmbedding()` を採用）
- [ ] リアルタイム文字起こし時のバッファリング戦略（チャンクサイズ）
- [ ] 声紋照合閾値の日本語音声での最適値（暫定 0.82、実測後調整）— 検証手順整備済み・実測待ち（TASK-27 / TASK-31）。`AppSettingsModel.embeddingMatchThreshold` を `SpeakerProfileStore` に配線済み・SettingsView に調整 UI（0.5〜0.95）あり。診断手段は3種類: (1) `EmbeddingSimilarityReport`（`Sources/SokkiKit/Diagnostics/`）は今回の録音1回分の diarization クラスタリング安定性（話者内/話者間の生 embedding 類似度分布）を診断するもので、録音間の再現性は測らない。(2) `SpeakerProfileStore` の `[TASK-27 実照合]` ログ（category "diagnostics"）は `resolveProfiles` が実際に使う「今回の集約 embedding vs 過去プロファイルの EMA embedding」の実スコアと閾値判定結果をそのまま出力するため、複数回録音して同一人物が既存プロファイルに再認識されるかはこちらで確認する。(3) DER 計測ハーネス（`docs/diarization-benchmark.md` の §7 / TASK-31）で分離精度自体を実測する。実音声での確認・閾値決定はユーザー実測待ち
- [ ] リアルタイム翻訳プロバイダの選定実証（Apple Translation の 19 言語で要件を満たすか / Gemini Live Translate のプレビュー安定性・コスト許容範囲）
- [ ] Core Audio Taps（ProcessTap）と SCStream のどちらを既定にするか（entitlement・権限フローの比較）

---

## 9. 設計方針：管理責任をアプリに持ち込まない

変化の激しいコンポーネントはアプリの外で管理し、アプリ本体は**音声 → テキスト → 表示/保存**というコアに集中する。

| コンポーネント | 管理者 | アプリの対応 |
|---|---|---|
| ScreenCaptureKit | Apple | 直接利用（ラッパー不要） |
| WhisperKit / SpeakerKit | Argmax (OSS) | SPM で追従 |
| SwiftData | Apple | 直接利用 |
| LLM | **ユーザー自身** | OpenAI 互換 HTTP 呼び出しのみ |

```swift
struct LLMSettings {
    var baseURL: URL     // 例: http://localhost:11434
    var apiKey: String?  // Ollama なら不要
    var model: String    // 例: "llama3.2"
}
```

---

*このドキュメントはプロジェクトの進行に合わせて随時更新する。*
