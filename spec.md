# sokki — アーキテクチャ仕様書

> 作成日: 2026-05-27
> ステータス: v1.0 (設計確定)
> 対象OS: macOS 15+ (Apple Silicon)

---

## 1. アプリ概要・差別化ポジション

**sokki**（速記）は、オンデバイス処理を基盤としつつリアルタイム翻訳など任意のクラウド機能を BYO key で追加できる、macOS ネイティブの音声文字起こし + 同時通訳アプリ。**ローカル完結は「既定 ON のプライバシーモード」として選択可能**（従来の絶対条件から格下げ）。

### 最大の差別化ポイント

**日本語話者分離の精度 + 声紋の永続記憶（オンデバイス） + リアルタイム翻訳（API ハイブリッド）**

- 声紋ベクトル（256 次元）を SwiftData に永続化し、セッションをまたいで同じ人を認識する（オンデバイス完結）
- コサイン類似度（vDSP）+ 指数移動平均更新で精度をセッションごとに向上させる
- 日本語 diarization をオンデバイスで実現するプロダクトは現時点で存在しない
- リアルタイム翻訳は Apple Translation（オンデバイス既定）と Gemini Live Translate 等（BYO key）を `TranslationProvider` で切替可能

### 競合との差別化マトリクス

| 条件 | sokki | MacWhisper Pro | WhisperMate | Granola | Japalog | SuperIntern |
|------|-------|---------------|-------------|---------|---------|-------------|
| ローカル完結（選択可能なプライバシーモード） | ✅ | ✅ | △ | ✅ | ✅ | ❌ |
| 高精度日本語 | ✅ | ✅ | ✅ | △ | ✅ | △ |
| 話者分離（オンデバイス） | ✅ | △ Beta | △ クラウド | ❌ | ✅ | △ |
| **声紋永続記憶** | **✅** | ❌ | ❌ | ❌ | ✅ | ❌ |
| **リアルタイム翻訳** | **✅ (Apple/BYO key)** | ❌ | ❌ | ❌ | ❌ | ✅ |
| LLM 柔軟交換 | ✅ | △ | △ | ❌ | ❌ | ❌ |
| 月額不要（BYO key） | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ ($20/月) |
| macOS SwiftUI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Homebrew Cask | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **全条件同時** | **✅** | ❌ | ❌ | ❌ | ❌ | ❌ |

---

## 2. 技術スタック

| レイヤー | 技術 | バージョン |
|---|---|---|
| 音声キャプチャ | Core Audio Taps（ProcessTap）または ScreenCaptureKit（単一 SCStream） | macOS 15+（D-1 / D-10） |
| 文字起こし | WhisperKit (`argmax-oss-swift`) | v1.0+ |
| 話者分離 | FluidAudio（推奨）/ SpeakerKit（Pyannote v4 Core ML） | FluidAudio: Apache 2.0 / SpeakerKit: MIT |
| 声紋 embedding | FluidAudio `extractEmbedding()`（256dim L2 正規化） | - |
| リアルタイム翻訳（optional） | Apple Translation（既定）/ Gemini Live Translate / Google Cloud Translation v3 / DeepL（BYO key） | macOS 15+ / 各 API |
| データ永続化 | SwiftData（SQLite） | macOS 15+ |
| UI | SwiftUI | macOS 15+ |
| 後処理 LLM（optional, 将来） | OpenAI 互換 / Gemini Flash HTTP | - |
| ベクトル演算 | Accelerate.framework（vDSP） | standard |

---

## 3. ディレクトリ構成

```
sokki/
├── Package.swift
├── Sources/sokki/
│   ├── App/
│   │   ├── sokkiApp.swift              # @main / WindowGroup / ModelContainer
│   │   └── AppDependencyContainer.swift # DI（actor 群の初期化）
│   ├── Audio/
│   │   ├── AudioCaptureManager.swift   # SCStream ラッパー (actor)
│   │   ├── AudioBuffer.swift           # リングバッファ + チャンク切り出し
│   │   └── AudioFileImporter.swift     # .mp4/.m4a/.wav/.mp3 読み込み
│   ├── Transcription/
│   │   ├── TranscriptionEngine.swift   # protocol
│   │   ├── WhisperKitEngine.swift      # actor 実装
│   │   └── TranscriptionPipeline.swift # @Observable、UI バインディング層
│   ├── Diarization/
│   │   ├── DiarizationEngine.swift     # protocol
│   │   ├── SpeakerKitEngine.swift      # actor 実装
│   │   └── DiarizationPipeline.swift   # 転写結果とのマージ
│   ├── SpeakerProfile/
│   │   ├── SpeakerProfileStore.swift   # 声紋照合・永続化 (actor) ← コア差別化
│   │   └── EmbeddingMatcher.swift      # コサイン類似度（vDSP）
│   ├── Session/
│   │   ├── SessionManager.swift        # @ModelActor
│   │   └── AudioPlaybackController.swift
│   ├── Export/
│   │   ├── ExportService.swift         # Exporter protocol dispatch
│   │   ├── MarkdownExporter.swift
│   │   ├── SRTExporter.swift
│   │   └── VTTExporter.swift
│   ├── Translation/
│   │   ├── TranslationProvider.swift       # protocol
│   │   ├── AppleTranslationProvider.swift  # オンデバイス（既定）
│   │   ├── GeminiLiveTranslateClient.swift # WebSocket（BYO key）
│   │   └── PCMConverter.swift              # Float32 → Int16 変換
│   ├── LLM/
│   │   └── OpenAICompatClient.swift        # 後処理（任意・将来）
│   ├── Models/                         # SwiftData @Model 群
│   │   ├── SessionModel.swift
│   │   ├── SegmentModel.swift
│   │   ├── SpeakerProfileModel.swift
│   │   └── AppSettingsModel.swift
│   └── UI/
│       ├── RecordingView/
│       │   ├── RecordingView.swift     # Mic / System / Both セグメント UI
│       │   ├── WaveformView.swift      # マイク=青、システム=赤
│       │   ├── LevelMeterView.swift
│       │   └── LiveTranscriptView.swift
│       ├── SessionListView/
│       │   ├── SessionListView.swift
│       │   └── SessionRowView.swift
│       ├── SessionDetailView/
│       │   ├── SessionDetailView.swift
│       │   ├── SegmentListView.swift
│       │   └── SpeakerLegendView.swift
│       ├── SpeakerProfileView/
│       │   └── SpeakerProfileView.swift
│       └── SettingsView/
│           └── SettingsView.swift
└── Tests/sokkiTests/
    ├── EmbeddingMatcherTests.swift
    ├── SpeakerProfileStoreTests.swift
    └── ExportTests.swift
```

---

## 4. コアコンポーネント設計

### 4.1 AudioCaptureManager（actor）

```swift
public enum AudioLane: Sendable { case microphone, system }

public struct AudioChunk: Sendable {
    public let lane: AudioLane
    public let pcmBuffer: AVAudioPCMBuffer  // 16kHz, mono, Float32
    public let capturedAt: Date
}

actor AudioCaptureManager: NSObject, SCStreamOutput {
    public enum CaptureMode { case micOnly, systemOnly, both }

    public private(set) var micStream:    AsyncStream<AudioChunk>!
    public private(set) var systemStream: AsyncStream<AudioChunk>!

    func startCapture(mode: CaptureMode) async throws
    func stopCapture() async
    var micLevelPublisher: AsyncStream<Float> { get }    // dBFS
    var systemLevelPublisher: AsyncStream<Float> { get }
}
```

**設計判断**: システム音声キャプチャは 2 方式を `AudioCaptureManager` 内で選択可能にする（D-1 改訂 / D-10）。
- **Core Audio Taps（推奨・既定）**: `CATapDescription` → Aggregate Device（`kAudioSubTapUIDKey` に `tapDescription.uuid.uuidString` を渡す）→ IOProc。Recap が MIT で参照実装（`ProcessTap` / `ProcessTapRecorder`）を提供。画面収録権限不要。
- **ScreenCaptureKit（代替）**: `SCStreamOutputType.audio`（システム）/ `.microphone`（マイク）で分岐する単一 SCStream。デュアル SCStream はデバイスアクセス競合リスクがあるため不採用（D-1）。

いずれも `AVAudioConverter` で 16 kHz mono Float32 に正規化してから下流へ。Both モードはシステム（tap）を先に起動し `tapStreamDescription` 確定後にマイクを起動（停止は逆順）。

### 4.2 TranscriptionEngine protocol / WhisperKitEngine

```swift
protocol TranscriptionEngine: Actor {
    func prepare() async throws
    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment]
    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<any TranscriptionSegment, Error>
    var isReady: Bool { get }
    var modelIdentifier: String { get }
}

protocol TranscriptionSegment: Sendable {
    var start: TimeInterval { get }
    var end: TimeInterval { get }
    var text: String { get }
    var isConfirmed: Bool { get }   // hypothesis vs confirmed
    var avgLogProb: Float { get }
}
```

- 30 秒スライディングウィンドウ + 5 秒オーバーラップ
- WhisperKit `LiveTranscriber` の Confirmed / Hypothesis 2 ストリーム出力を活用

### 4.3 DiarizationEngine protocol / SpeakerKitEngine

```swift
struct DiarizationSegment: Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let speakerID: String       // "SPEAKER_00" 等（エンジン内部ラベル）
    let embedding: [Float]?     // 256-dim WeSpeaker ResNet34
}

protocol DiarizationEngine: Actor {
    func prepare() async throws
    func diarize(audioArray: [Float]) async throws -> DiarizationResult
    var isReady: Bool { get }
}
```

**エンジン選定（D-5 / D-11）**: `SpeakerKit` は WhisperKit との統合が最も容易だが、v1.0 時点で声紋 embedding を直接公開しない（`SpeakerKitEngine` は現状 `embedding: nil`）。声紋永続記憶（最大の差別化）には embedding が必須のため、**`FluidAudio` を推奨エンジンとする**（`extractEmbedding()` が public・256 次元 L2 正規化済みで `SpeakerProfileStore` 設計と完全一致）。両者は同 protocol でドロップイン交換可能。リアルタイム話者分離は FluidAudio Sortformer（80ms・macOS 15+・日本語 DER 12.7%）を Phase 2 以降で評価する。

### 4.4 SpeakerProfileStore（actor）— 最重要差別化機能

```swift
actor SpeakerProfileStore {
    func resolveProfiles(from: DiarizationResult) async throws -> [String: SpeakerProfileModel]
    func rename(profileID: UUID, to name: String) throws
    func allProfiles() throws -> [SpeakerProfileModel]
}
```

**照合フロー**:
1. セッション内の同 speakerID セグメントの embedding を平均 → L2 正規化
2. `EmbeddingMatcher.bestMatch(query:candidates:)` でコサイン類似度（vDSP）
3. 閾値 ≥ 0.82 → 既存プロファイルに EMA 更新（alpha = 0.1）
4. 閾値未満 → 新規 `SpeakerProfileModel` を SwiftData に INSERT

**閾値の設定方針**: 0.82 は WeSpeaker VoxCeleb 英語評価の EER 付近。
日本語では 0.78〜0.85 で実測後調整。`AppSettingsModel` でユーザー変更可能にする。

### 4.5 EmbeddingMatcher

```swift
struct EmbeddingMatcher {
    let threshold: Float  // default: 0.82

    func bestMatch(query: [Float], candidates: [SpeakerProfileModel]) -> SpeakerProfileModel?

    // vDSP_dotpr / vDSP_svesq で高速演算（256次元、十分高速）
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float
}
```

### 4.6 TranslationProvider protocol — リアルタイム翻訳（新規）

> **完全な設計は [`docs/translation-architecture.md`](docs/translation-architecture.md)**（3案統合 + Swift6/Apple API 敵対的レビュー済み）。以下は要点のみ。Apple Translation 経路は実機 PoC が前提（同ドキュメント §0）。

```swift
public struct TranslationInput: Sendable, Identifiable {
    public let id: UUID                  // = clientID。原文セグメントと同一キー（順序逆転に強い）
    public let text: String
    public let sourceTime: TimeInterval
}
public struct TranslationOutput: Sendable, Identifiable {
    public let id: UUID                  // 対応する TranslationInput.id をエコーバック
    public let translatedText: String
    public let isConcluded: Bool
    public let sourceTime: TimeInterval
}

public protocol TranslationProvider: Actor {
    nonisolated var providerID: String { get }   // 監査タグ
    nonisolated var isOnDevice: Bool { get }     // Gate が actor hop なしに参照
    func prepare(source: Locale.Language, target: Locale.Language) async throws
    func translateStream(_ inputs: AsyncStream<TranslationInput>)
        -> AsyncThrowingStream<TranslationOutput, Error>
    func teardown() async                        // socket/URLSession を確実クローズ（冪等）
}
```

**責務分離（知能は provider に持たせず以下に集約）**:
- `TranslationGate`（純粋関数・fail-closed）: クラウド送信可否を一元判定。`translationEnabled × privacyMode × isOnDevice × 明示選択 × key有無` の真理値表。**「ユーザー明示選択」と「auto の自動フォールバック」を区別**し、privacy ON では自動クラウド送信を拒否、明示選択のみオプトイン許可。
- `TranslationRouter`（actor）: `LanguageAvailability.status` で Apple 対応判定 → 未対応なら BYO 自動FB。
- `TranslationCoordinator`（@MainActor 状態機械）: `prepare()`〜`teardown()` の間だけ provider 生存。設定変化で即 teardown。

**プロバイダ実装方針**:
- `AppleTranslationProvider`（既定・オンデバイス）: `TranslationSession` は公開 init を持たず `.translationTask` closure 内でのみ有効。**closure 外へ出すと fatal error**。常駐の不可視ホスト View 内 drain ループで処理し、actor 境界を越えるのは値型のみ。
- `GeminiLiveTranslateClient`（BYO key）: `URLSessionWebSocketTask`。プレビューのため実験的扱い。
- `DeepLProvider`（BYO key）: REST（キーがシンプルで BYO の現実的第一候補）。
- `GoogleCloudTranslationV3Provider`（BYO key）: v3 は OAuth2/サービスアカウント必須（生 API キー不可）→ 着手は後回し。

---

## 5. SwiftData モデル

### SpeakerProfileModel

```swift
@Model final class SpeakerProfileModel {
    @Attribute(.unique) var id: UUID
    var displayName: String          // ユーザー編集可能（"田中さん" 等）
    var embeddingData: Data          // [Float] シリアライズ (256 × 4 = 1024 bytes)
    var embeddingCount: Int          // EMA の重み管理
    var createdAt: Date
    var lastSeenAt: Date
    var colorHex: String             // 話者カラー（UI 表示）

    @Relationship(deleteRule: .nullify, inverse: \SegmentModel.speakerProfile)
    var segments: [SegmentModel]

    // Data ↔ [Float] computed property
    var embedding: [Float] { get set }

    // 指数移動平均更新（alpha=0.1、count>10 で alpha 低減予定）
    func updateEmbedding(with: [Float], alpha: Float = 0.1)
}
```

### SessionModel

```swift
@Model final class SessionModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var audioFilePath: String        // URL.path（SwiftData は URL 非対応）
    var durationSeconds: Double
    var captureMode: String          // "mic" | "system" | "both" | "file"

    @Relationship(deleteRule: .cascade)
    var segments: [SegmentModel]
}
```

### SegmentModel

```swift
@Model final class SegmentModel {
    @Attribute(.unique) var id: UUID
    var start: Double
    var end: Double
    var text: String
    var avgLogProb: Float
    var speakerLabel: String?        // "SPEAKER_00"（エンジン内部ラベル保持）
    var speakerProfile: SpeakerProfileModel?
    var session: SessionModel?
}
```

### AppSettingsModel

```swift
@Model final class AppSettingsModel {
    @Attribute(.unique) var id: UUID = UUID()
    var llmBaseURL: String?
    var llmApiKey: String?
    var llmModel: String?
    var transcriptionEngine: String = "whisperkit"
    var whisperModelVariant: String = "large-v3-turbo"
    var diarizationEngine: String = "fluidaudio"   // "fluidaudio" | "speakerkit"
    var diarizationEnabled: Bool = true
    var numberOfSpeakers: Int = 0    // 0 = 自動
    var embeddingMatchThreshold: Float = 0.82
    var embeddingEMAAlpha: Float = 0.1

    // --- 音声キャプチャ ---
    var systemAudioBackend: String = "coreaudiotap"  // "coreaudiotap" | "screencapturekit"

    // --- プライバシー / 翻訳 ---
    var privacyModeEnabled: Bool = true              // 既定 ON: クラウド送信を遮断
    var translationEnabled: Bool = false             // 翻訳 ON/OFF トグル
    var translationProvider: String = "auto"         // "auto" | "apple" | "gemini" | "googlev3" | "deepl"
    var translationSourceLanguage: String = "ja"
    var translationTargetLanguage: String = "en"
    // BYO key は SwiftData に置かず KeychainStore で管理（D-17）。ここには保持しない
}
```

---

## 6. Package.swift 依存関係

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "sokki",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "sokki", targets: ["sokki"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift",
            from: "1.0.0"
        ),
        // 話者分離 + 声紋 embedding（推奨）。extractEmbedding() が public（Apache 2.0）
        // 調査時点の最新は 0.12.4。採用前に最新版を確認すること
        .package(
            url: "https://github.com/FluidInference/FluidAudio",
            from: "0.12.4"
        ),
    ],
    targets: [
        .executableTarget(
            name: "sokki",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/sokki",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "sokkiTests",
            dependencies: ["sokki"],
            path: "Tests/sokkiTests"
        )
    ]
)
```

---

## 7. UI 設計方針

### RecordingView（Kanary 踏襲）

- 上部にセグメントコントロール: `Mic` / `System` / `Both`
- 上部右に **ローカル/API インジケーター**（プライバシーモード状態を明示）と **翻訳 ON/OFF トグル**
- 波形表示: マイク = 青（#3B82F6）、システム = 赤（#EF4444）
  - 左右分割で常時表示、50ms 更新周期
  - ピークメーター: -60〜0 dB、クリッピング時赤点灯
- 中央にライブ文字起こし（翻訳 ON 時は 2 レーン: 原文 / 訳文）:
  - Confirmed / concluded テキスト（黒、確定済み）
  - Hypothesis / tentative テキスト（グレー、仮テキスト）
- 下部に大きな録音ボタン + 経過時間

### 翻訳字幕オーバーレイ（新規・Phase 2.5）

- 会議ウィンドウ横にフローティング表示（原文 + 訳文の 2 レーン）
- 翻訳 OFF / プライバシーモードで `isOnDevice == false` プロバイダ未許可時は非表示

### SpeakerProfileView（差別化 UI）

- 声紋プロファイルカード一覧
- インライン名前編集
- 最終検出日時、過去セッション出現回数
- 声紋削除（プロファイルリセット）

### SessionDetailView

- セグメント一覧（クリックで音声再生）
- 話者カラーバー（左端）
- 右上にエクスポートボタン（Markdown / SRT / VTT / プレーンテキスト）

---

## 8. 開発フェーズ

### Phase 1 — MVP（目標: 2〜3 週間）

| 機能 | ファイル |
|---|---|
| マイク単独キャプチャ | `AudioCaptureManager` |
| WhisperKit バッチ文字起こし（停止後処理） | `WhisperKitEngine` |
| セッション保存 | `SessionModel`, `SegmentModel`, `SessionManager` |
| セッション一覧・詳細表示 | `SessionListView`, `SessionDetailView` |
| Markdown エクスポート | `MarkdownExporter` |
| 最小 RecordingView（波形なし） | `RecordingView` |

### Phase 2 — システム音声 + リアルタイム

- システム音声キャプチャ（Both / System タブ）
- リアルタイムストリーミング文字起こし（LiveTranscriber）
- 波形 / レベルメーター表示
- セグメント同期音声再生

### Phase 2.5 — リアルタイム翻訳（新規）

- `TranslationProvider` protocol + `AppleTranslationProvider`（オンデバイス既定）
- `GeminiLiveTranslateClient`（WebSocket, `PCMConverter` で Float32→Int16, BYO key）
- 翻訳字幕 2 レーン UI + フローティングオーバーレイ
- 翻訳 ON/OFF トグル + プロバイダ/言語選択（SettingsView）

### Phase 3 — 話者分離・声紋永続化

- 話者分離エンジン連携（**FluidAudio 推奨** / SpeakerKit 代替）
- `SpeakerProfileStore` 実装 + **diarization → Store 配線（embedding nil の解消）**
- `SpeakerProfileView` UI
- 話者カラーバー付き `SessionDetailView`

### Phase 4 — エクスポート拡充・エンジン追加

- SRT / VTT エクスポート（実装済み・確認のみ）
- Apple SpeechAnalyzer エンジン（macOS 26+）
- ファイルインポート（.mp4 / .m4a / .wav / .mp3）

### Phase 5 — 配布・プライバシー

- Homebrew Cask 配布設定
- プライバシーモード切替 UI + ローカル/API インジケーター

### Phase 6 — LLM 後処理（任意・将来 / 当面スコープ外）

- 要約・アクション抽出・会議後チャット（OpenAI 互換 / Gemini Flash）
- `OpenAICompatClient` + `SpeakerNamingService`（話者名推定はここに含む）

---

## 9. 設計判断ログ

| # | 判断 | 理由 |
|---|------|------|
| D-1 | システム音声は単一 SCStream（代替）/ Core Audio Taps（既定） | デュアル SCStream はデバイスアクセス競合リスクがあるため不採用。SCStream は OutputType 分岐の単一構成に限定。D-10 で Core Audio Taps を既定に追加 |
| D-10 | Core Audio Taps（ProcessTap）を既定のシステム音声キャプチャに | 画面収録権限不要、プロセス単位タップ、Recap の MIT 参照実装あり。SCStream は権限が必要なため代替に位置づけ |
| D-11 | 話者分離は FluidAudio を推奨（SpeakerKit は代替） | SpeakerKit v1.0 は声紋 embedding を公開せず `embedding: nil`。声紋永続記憶に必須の embedding を `extractEmbedding()` で確実に取得できる FluidAudio を推奨。`DiarizationEngine` protocol でドロップイン交換 |
| D-12 | リアルタイム翻訳は `TranslationProvider` 抽象 + Apple Translation 既定 | オンデバイス・無料・プライバシーモード適合を既定に。Gemini Live Translate 等のクラウドは BYO key オプションとし、プレビュー/高コストを実験的扱い |
| D-13 | ローカル完結はプライバシーモード（既定 ON）に格下げ | 完全ローカルを絶対条件から外し選択可能モード化。`isOnDevice == false` プロバイダは明示オプトイン時のみ起動許可 |
| D-14 | クラウド送信可否は `TranslationGate.evaluate`（純粋関数・fail-closed）に一元化 | provider に権限判定を分散させない。真理値表を実機なしで全網羅テスト。「明示選択」と「自動FB」を区別し privacy ON では自動クラウドを拒否（`docs/translation-architecture.md` §5） |
| D-15 | 翻訳 provider は `prepare()`〜`teardown()` の間だけ生存 | クラウド socket を長命にしない構造的プライバシー担保。privacy/enabled 変化で即 teardown |
| D-16 | `TranslationSession` は `.translationTask` closure 内に閉じ、常駐ホストの drain ループで処理 | closure 外で使うと fatal error。actor へ越境させるのは値型（id/text）のみ。**長時間 drain ループの成立は実機 PoC で要検証** |
| D-17 | BYO key は SwiftData ではなく Keychain（`KeychainStore` 単一アクセス点） | 平文保存を避ける。`AppSettingsModel.translationApiKey` は廃止し Keychain へ移行 |
| D-2 | 閾値 0.82 を初期値に | VoxCeleb EER 付近だが日本語では要実測調整。AppSettings で変更可 |
| D-3 | EMA alpha=0.1 | セッションを重ねるほど精緻化。count>10 での alpha 低減を Phase 3 で追加 |
| D-4 | `[Float]→Data` 保存 | SwiftData は `[Float]` を Attribute 直サポートしない。1024 bytes/プロファイルは合理的 |
| D-5 | `DiarizationEngine` protocol 化 | SpeakerKit / FluidAudio OfflineDiarizer を将来ドロップイン評価できるよう抽象化 |
| D-6 | Phase 1 MVP はバッチ文字起こし | リアルタイムストリーミングより動作確認が容易。ストリームは Phase 2 で追加 |
| D-7 | xcodeproj を xcodegen で生成・管理 | `ENABLE_DEBUG_DYLIB` / Signing & Capabilities は SPM only では設定不可。`project.yml` で宣言的に管理 |
| D-8 | `SokkiKit` (library) + `sokki` (executable) に分離 | `RenderPreview` / `ExecuteSnippet`（Xcode MCP）は Library target でのみ動作するため |
| D-9 | Phase 1 は `AVAudioEngine`（マイクのみ）、Phase 2 でシステム音声を **Core Audio Taps（ProcessTap）** へ拡張（D-10） | Screen Recording 権限不要で MVP を先行確認できる。Phase 2 の system レーンは SCStream ではなく Core Audio Taps を既定（SCStream は代替）。`AudioCaptureManager` は `CaptureMode` + `systemAudioBackend` で分岐 |

---

## 10. 検証方法

```bash
# ユニットテスト
swift test                            # 全 20 テスト
swift test --filter EmbeddingMatcherTests
swift test --filter ExportTests
swift test --filter SnapshotTests     # UI スナップショット比較

# ビルド確認
swift build                           # CLI
xcodegen generate && open sokki.xcodeproj  # Xcode

# Xcode MCP（Claude Code から）
# BuildProject → ビルド成功確認
# RenderPreview → 各 View の PNG 生成
# RunAllTests  → テスト実行

# 手動フロー確認
# 1. Xcode で ⌘R
# 2. マイク権限を許可
# 3. 録音開始（Mic モード）→ 話す → 停止
# 4. SessionListView で結果確認
# 5. Markdown エクスポート → クリップボードに貼り付けて確認
```

---

## 11. ディレクトリ構成（2026-05-27 更新）

```
sokki/
├── sokki.xcodeproj/        # xcodegen が project.yml から生成
├── project.yml             # xcodegen 設定（ターゲット・ビルド設定）
├── Package.swift           # SPM 外部依存（WhisperKit / SpeakerKit）
├── Package.resolved
├── Info.plist              # アプリバンドル情報
├── sokki.entitlements      # マイク / ネットワーク 権限
├── nix/                    # Nix devshell（just コマンド等）
├── justfile                # just build / test / smoke
├── Sources/
│   ├── SokkiKit/           # ← Library target（全ビジネスロジック・UI）
│   │   ├── App/            AppDependencyContainer, AppFactory
│   │   ├── Audio/          AudioCaptureManager, PermissionManager
│   │   ├── Transcription/  TranscriptionEngine, WhisperKitEngine, TranscriptionPipeline
│   │   ├── Diarization/    DiarizationEngine, SpeakerKitEngine
│   │   ├── SpeakerProfile/ SpeakerProfileStore, EmbeddingMatcher
│   │   ├── Session/        SessionManager
│   │   ├── Export/         ExportService, MarkdownExporter, SRTExporter
│   │   ├── LLM/            OpenAICompatClient
│   │   ├── Models/         SessionModel, SegmentModel, SpeakerProfileModel, AppSettingsModel
│   │   ├── UI/             ContentView + 各 View ファイル
│   │   └── Mocks/          PreviewMocks（#if DEBUG）
│   └── sokki/              # ← Executable target（@main のみ）
│       └── App/            sokkiApp.swift
└── Tests/sokkiTests/       # テストスイート（20 テスト）
```

---

*このドキュメントはプロジェクトの進行に合わせて随時更新する。*
