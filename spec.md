# sokki — アーキテクチャ仕様書

> 作成日: 2026-05-27
> ステータス: v1.0 (設計確定)
> 対象OS: macOS 15+ (Apple Silicon)

---

## 1. アプリ概要・差別化ポジション

**sokki**（速記）は、ローカル完結の macOS ネイティブ音声文字起こしアプリ。

### 最大の差別化ポイント

**日本語話者分離の精度 + 声紋の永続記憶**

- 声紋ベクトル（256 次元）を SwiftData に永続化し、セッションをまたいで同じ人を認識する
- コサイン類似度（vDSP）+ 指数移動平均更新で精度をセッションごとに向上させる
- 日本語 diarization をローカル完結で実現するプロダクトは現時点で存在しない

### 競合との差別化マトリクス

| 条件 | sokki | MacWhisper Pro | WhisperMate | Granola | Japalog |
|------|-------|---------------|-------------|---------|---------|
| ローカル完結 | ✅ | ✅ | △ | ✅ | ✅ |
| 高精度日本語 | ✅ | ✅ | ✅ | △ | ✅ |
| 話者分離 | ✅ | △ Beta | △ クラウド | ❌ | ✅ |
| **声紋永続記憶** | **✅** | ❌ | ❌ | ❌ | ✅ |
| LLM 柔軟交換 | ✅ | △ | △ | ❌ | ❌ |
| macOS SwiftUI | ✅ | ✅ | ✅ | ✅ | ✅ |
| Homebrew Cask | ✅ | ✅ | ❌ | ❌ | ❌ |
| **全条件同時** | **✅** | ❌ | ❌ | ❌ | ❌ |

---

## 2. 技術スタック

| レイヤー | 技術 | バージョン |
|---|---|---|
| 音声キャプチャ | ScreenCaptureKit（単一 SCStream） | macOS 15+ |
| 文字起こし | WhisperKit (`argmax-oss-swift`) | v1.0+ |
| 話者分離 | SpeakerKit（Pyannote v4 Core ML） | v0.18+ |
| データ永続化 | SwiftData（SQLite） | macOS 15+ |
| UI | SwiftUI | macOS 15+ |
| LLM（optional） | OpenAI 互換 HTTP | - |
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
│   ├── LLM/
│   │   └── OpenAICompatClient.swift
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

**設計判断**: デュアル SCStream（Blackbox 実装）はデバイスアクセス競合リスクがある。
`SCStreamOutputType.audio`（システム）/ `.microphone`（マイク）で分岐する単一 SCStream を採用。
`AVAudioConverter` で 16 kHz mono Float32 に正規化してから下流へ。

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

FluidAudio `OfflineDiarizer` も同 protocol でドロップイン評価可能（将来）。

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
    var diarizationEnabled: Bool = true
    var numberOfSpeakers: Int = 0    // 0 = 自動
    var embeddingMatchThreshold: Float = 0.82
    var embeddingEMAAlpha: Float = 0.1
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
- 波形表示: マイク = 青（#3B82F6）、システム = 赤（#EF4444）
  - 左右分割で常時表示、50ms 更新周期
  - ピークメーター: -60〜0 dB、クリッピング時赤点灯
- 中央にライブ文字起こし:
  - Confirmed テキスト（黒、確定済み）
  - Hypothesis テキスト（グレー、仮テキスト）
- 下部に大きな録音ボタン + 経過時間

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

### Phase 3 — 話者分離・声紋永続化

- SpeakerKit 連携（`SpeakerKitEngine`）
- `SpeakerProfileStore` 実装
- `SpeakerProfileView` UI
- 話者カラーバー付き `SessionDetailView`

### Phase 4 — エクスポート拡充・エンジン追加

- SRT / VTT エクスポート
- Apple SpeechAnalyzer エンジン（macOS 26+）
- ファイルインポート（.mp4 / .m4a / .wav / .mp3）

### Phase 5 — LLM 連携・配布

- OpenAI 互換エンドポイント（話者名推定・サマリー）
- Homebrew Cask 配布設定
- `OpenAICompatClient` + `SpeakerNamingService`

---

## 9. 設計判断ログ

| # | 判断 | 理由 |
|---|------|------|
| D-1 | 単一 SCStream 方式 | デュアル SCStream はデバイスアクセス競合リスクがある。Apple 推奨の OutputType 分岐を採用 |
| D-2 | 閾値 0.82 を初期値に | VoxCeleb EER 付近だが日本語では要実測調整。AppSettings で変更可 |
| D-3 | EMA alpha=0.1 | セッションを重ねるほど精緻化。count>10 での alpha 低減を Phase 3 で追加 |
| D-4 | `[Float]→Data` 保存 | SwiftData は `[Float]` を Attribute 直サポートしない。1024 bytes/プロファイルは合理的 |
| D-5 | `DiarizationEngine` protocol 化 | SpeakerKit / FluidAudio OfflineDiarizer を将来ドロップイン評価できるよう抽象化 |
| D-6 | Phase 1 MVP はバッチ文字起こし | リアルタイムストリーミングより動作確認が容易。ストリームは Phase 2 で追加 |
| D-7 | xcodeproj を xcodegen で生成・管理 | `ENABLE_DEBUG_DYLIB` / Signing & Capabilities は SPM only では設定不可。`project.yml` で宣言的に管理 |
| D-8 | `SokkiKit` (library) + `sokki` (executable) に分離 | `RenderPreview` / `ExecuteSnippet`（Xcode MCP）は Library target でのみ動作するため |
| D-9 | Phase 1 は `AVAudioEngine`、Phase 2 で `SCStream` に切替 | Screen Recording 権限不要で MVP を先行確認できる。`AudioCaptureManager` は `CaptureMode` で分岐 |

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
