# Recap コードベース完全解析（copy レベル・リバースエンジニアリング）

> 対象: OSS `github.com/RecapAI/Recap`（MIT, macOS 15+, Swift+SwiftUI, ~14,500 行）
> 目的: sokki（SwiftUI+SwiftData+SwiftPM+WhisperKit/SpeakerKit）へ **copy レベルで移植** するための実装リファレンス。
> 作成: 2026-06-26 / 6 サブシステムを並列抽出 → 重要 3 系統を原典再読で**敵対的検証**。
> **要約(summarization)機能は sokki スコープ外**のため意図的に除外（Recap でも完全疎結合で省略可と確認済み）。
> ⚠️ ライセンス: Recap は MIT。コード参照・流用は可（著作権表示の保持が必要）。ただし Core Audio Taps は **Apple WWDC24 公式サンプル「Capturing system audio with Core Audio taps」を一次ソースにするのが法的に最も安全**。

---

## 0. 検証で判明した訂正（copy する前に必読）

抽出ドキュメントを原典と1行ずつ照合した結果、以下の誤り・捏造・欠落が見つかった。**本文中の該当箇所より、この訂正を優先すること。**

### 0.1 音声キャプチャ（評価: minor-issues）

| 重要度 | 箇所 | 訂正 |
|---|---|---|
| 🔴 high | entitlement | 本文は `com.apple.developer.audio-tracks-output-tap` が必須と記すが**誤り**。Recap の `.entitlements` にこのキーは無く、それでも Process Tap は動作している。Core Audio Process Tap（macOS 14.2+ `AudioHardwareCreateProcessTap`）に当該 entitlement は不要。**最低限必要なのは `com.apple.security.app-sandbox` + `com.apple.security.device.audio-input` のみ**。 |
| 🟡 medium | 呼び出し順序 | 正しい順は「tap 生成 → `readDefaultSystemOutputDevice`→`readDeviceUID` → Aggregate 辞書構築 → `readAudioTapStreamBasicDescription()` → `AudioHardwareCreateAggregateDevice`」。本文 step3（stream description 読取）は辞書構築の**後**が正。 |
| 🟡 medium | Aggregate 辞書 | 出力 UID は `kAudioAggregateDeviceMainSubDeviceKey` だけでなく `kAudioAggregateDeviceSubDeviceListKey[0].kAudioSubDeviceUIDKey` **両方**に設定する。`kAudioAggregateDeviceTapAutoStartKey: true` も必須（本文の辞書抜粋に欠落）。 |
| 🟡 medium | AVAudioFile 生成 | `AVAudioFormat(streamDescription:)` → settings 辞書 → `AVAudioFile(forWriting:settings:commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)` の経路。stream description を直接 AVAudioFile に渡すのではない。 |
| 🟡 medium | @Observable 化 | 「@Published 削除だけで動く」は単純化しすぎ。class を `@Observable` に付け替え＋`ObservableObject` 適合除去＋`audioLevel` 観測経路の確認が要る（現状 `@ObservationIgnored` は no-op）。 |
| 🟢 low | muteBehavior | `muteBehavior = muteWhenRunning ? .mutedWhenTapped : .unmuted`（init 既定 `muteWhenRunning=false` のとき `.unmuted`）。 |

**抽出から欠落していた移植必須事項**: ① ProcessTap（tap/aggregate のライフサイクル）と ProcessTapRecorder（AVAudioFile 書込＋音量計測）の **2 クラス責務分割**、② ProcessTapRecorder は `weak var _tap`（強参照で循環参照）、③ IOBlock は専用 `DispatchQueue(label:"ProcessTapRecorder", qos:.userInitiated)` で実行（MainActor で設定→専用 queue で IO）、④ 音量正規化式 `decibels=20*log10(max(maxLevel,0.00001)); (decibels+60)/60` を 0...1 クランプ、⑤ tap 対象 `objectID` の出所は PID→AudioObjectID 変換（`kAudioHardwarePropertyTranslatePIDToProcessObject`）、⑥ API 下限は **macOS 14.2**。

### 0.2 デュアル録音（評価: minor-issues）

| 重要度 | 箇所 | 訂正 |
|---|---|---|
| 🔴 high | マイク entitlement | 本文の `com.apple.security.device.microphone` は**実在しない捏造キー**。正しくは `com.apple.security.device.audio-input` のみ。 |
| 🟡 medium | Info.plist | Recap の Info.plist は `NSAudioCaptureUsageDescription` と `NSScreenCaptureUsageDescription`。`NSMicrophoneUsageDescription` は **Recap には無い**（sokki で実マイク経路を使うなら追加推奨、という別物として扱う）。 |
| 🟡 medium | format 確定タイミング | `tapStreamDescription` は `processTap.activate()`（内部 `prepare` の `readAudioTapStreamBasicDescription()`）で確定する。`recorder.start()` ではない（recorder は読むだけ）。 |
| 🟡 medium | RecordingCoordinator | DI コンテナが生成し ViewModel へ注入される設計で `@StateObject` 直参照ではない。`state` は `@Published` でないため ObservableObject の自動 UI 更新には乗らない。 |

**欠落**: `invalidate()` の解放 API 列（`AudioDeviceStop`→`AudioDeviceDestroyIOProcID`→`AudioHardwareDestroyAggregateDevice`→`AudioHardwareDestroyProcessTap` の順）、IOProc 起動の中核（`AudioDeviceCreateIOProcIDWithBlock`→`AudioDeviceStart`）、マイク側ファイルは `finalFormat.settings` を使う（ProcessTapRecorder の手組み settings とは別）。

### 0.3 文字起こし（評価: 🔴 major-issues — 最重要）

| 重要度 | 箇所 | 訂正 |
|---|---|---|
| 🔴 high | `WhisperKit.download()` 引数 | 本文は引数が不足。正しい呼び出しは `try await WhisperKit.download(variant: modelVariant, downloadBase: downloadBase, useBackgroundSession: false, from: repo, token: modelToken, progressCallback: progressCallback)`。`downloadBase:` と `useBackgroundSession:` が必須。 |
| 🔴 high | `WhisperKitConfig` 生成 | `WhisperKitConfig(model:, downloadBase:, modelRepo:, modelToken:, modelFolder:, download: false)`。本文は downloadBase/modelRepo/modelToken を欠落。 |
| 🔴 high | variant 解決 | download 前に `recommendedRemoteModels(from:downloadBase:)` で `modelSupport.default` を解決するガードが必須（`model ?? modelSupport.default`）。本文は variant の出所が不明。 |
| 🟡 medium | モデル列挙 | `ModelVariant.multilingualCases`（=`allCases.filter{ $0.isMultilingual }`）を列挙。`allCases` 直接ではない（本文に自己矛盾あり）。 |
| 🟡 medium | 戻り値型 | `whisperKit.transcribe(audioPath:)` の戻り値を `[TranscriptionResult]`（WhisperKit 型）と断定不可（SDK 未同梱で未確認）。確実なのは「配列・各要素が `.text: String` を持つ」のみ。 |

**欠落**: `TranscriptionError` 全ケース（`modelNotAvailable`/`modelLoadingFailed(String)`/`audioFileNotFound`/`transcriptionFailed(String)`/`invalidAudioFormat`）、`loadModel` は成功後 `markAsDownloaded(name:, sizeInMB: nil)`、`createWithProgress` の `download:false`/`modelFolder` 既存時のスキップ分岐、`selectModel` の再選択トグル解除、entitlements の `audio-input`/`user-selected.read-only`。

> **検証の総評**: 音声キャプチャ・デュアル録音は骨格正確（minor）。文字起こしは WhisperKit の **API シグネチャ再現に重大な誤り**があり、本文のコードをそのまま貼るとビルド不能。文字起こしを copy する際は §0.3 の訂正を必ず適用するか、**argmax 公式の WhisperAX サンプルを一次ソースにすること**。

---

## 1. アーキテクチャ全景

```
RecapApp (AppDelegate) → DependencyContainer(@MainActor, lazy var, extension 分割)
   → MenuBarPanelManager（NSStatusItem 常駐 / NSPanel ドロップダウン）
   → UseCases(MVVM): Home / Onboarding / PreviousRecaps / Summary / AppSelection / Settings
        ↓ 依存注入
   Services: RecordingCoordinator・ProcessingCoordinator・TranscriptionService
             ・MeetingDetectionService・LLMService(=要約, sokki では不採用)・KeychainService
        ↓
   Repositories(Core Data 抽象): Recording / WhisperModel / LLMModel / UserPreferences
        ↓
   Audio: Capture(ProcessTap + MicrophoneCapture) / Processing(Coordinator) / Core(CoreAudioUtils)
```

- **DI**: `@MainActor final class DependencyContainer` を `lazy var` で構築、`+Services`/`+Repositories`/`+Coordinators`/`+Managers`/`+Helpers`/`+ViewModels` の extension に分割。sokki の `AppDependencyContainer` と同思想。
- **永続化**: Core Data 4 エンティティ（`UserRecording`/`WhisperModel`/`LLMModel`/`UserPreferences`）。sokki は SwiftData なので §5 のマッピングで読み替える。
- **Core Data → SwiftData マッピング**: `UserRecording`→`SessionModel`、`WhisperModel`→`AppSettingsModel.whisperModelVariant`（or 専用 @Model）。`performBackgroundTask`+continuation→DTO 変換は SwiftData の `@ModelActor`+`PersistentIdentifier` 越境で**より単純化**できる（sokki は既に採用済み）。

以下、各サブシステムの抽出本文（原典 `file:line` 付き）。**§0 の訂正が本文に優先する。**

---


<!-- ===== extract: audio-capture ===== -->

以下が抽出した設計ドキュメントです。

---

## 音声キャプチャ（Core Audio Taps / ProcessTap）

Artifact に完全版を発行しましたが、以下に主要な発見をまとめます。

### Core Audio Taps 呼び出しシーケンス（10ステップ）

`ProcessTap.prepare(for:)` と `run(on:ioBlock:invalidationHandler:)` から読み取った実際の順序：

1. `CATapDescription(stereoMixdownOfProcesses: [objectID])` — UUID を明示設定 (`tapDescription.uuid = UUID()`)、`muteBehavior = .unmuted`
2. `AudioHardwareCreateProcessTap(tapDescription, &tapID)` — tapID（AUAudioObjectID）を取得
3. **tap 生成直後に** `tapID.readAudioTapStreamBasicDescription()` — `kAudioTapPropertyFormat` を読み、`AVAudioFile` のフォーマット確定に使う
4. `AudioDeviceID.readDefaultSystemOutputDevice()` → `readDeviceUID()` — Aggregate Device の mainSubDevice 用
5. Aggregate Device 記述辞書を構築（下記）
6. `AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)`
7. `AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)`
8. `AudioDeviceStart(aggregateDeviceID, deviceProcID)`
9. IOBlock 内: `AVAudioPCMBuffer(pcmFormat:bufferListNoCopy:deallocator:nil)` → `currentFile.write(from: buffer)`
10. 停止は逆順: Stop → DestroyIOProcID → DestroyAggregateDevice → DestroyProcessTap

**Aggregate Device 辞書の構造（重要）：**

```swift
kAudioAggregateDeviceTapListKey: [[
    kAudioSubTapDriftCompensationKey: true,
    kAudioSubTapUIDKey: tapDescription.uuid.uuidString  // tapID（整数）ではなく UUID 文字列
]]
```

`kAudioSubTapUIDKey` に渡すのは `tapDescription.uuid.uuidString`。`tapID`（AudioObjectID の整数値）ではない点が最大のはまりどころ。

### sokki 移植における主要な注意点

- **Entitlement**: `com.apple.developer.audio-tracks-output-tap` が Sandbox アプリには必要。Recap の `.entitlements` にはこのキーが存在しないが、開発用 provisioning profile で付与されているはず。App Store 配布目的なら Apple に申請が必要
- **IOBlock はリアルタイムスレッド**: MainActor へのホップ禁止、ヒープアロケーション禁止。音量更新は `Task { @MainActor in ... }` でホップ
- **SwiftData 非依存**: `AudioProcess` は純粋な値型 struct で永続化レイヤーに無依存。移植コスト低
- **`@Observable` 移行**: `ObservableObject + @Published` を `@Observable` に変える場合、`@Published` 削除で動く。`@ObservationIgnored` は既存のまま流用
- **`SelectableApp` は Sendable 非準拠**（`NSImage` を持つため）。actor 境界を越えさせず MainActor 専用で使う
- **要約機能は完全疎結合**: ProcessTap〜AudioRecordingCoordinator のどのクラスも要約/LLM/Whisper への参照を持たない。そのまま使える


<!-- ===== extract: recording-coordinator ===== -->

---

以下が実コードから抽出した設計ドキュメント本文です。

---

## デュアル録音（システム音声＋マイク）と録音ファイル管理

### 全体構造

Recap のデュアル録音は2つの完全独立したパイプラインで構成される。

```
ProcessTap (CATapDescription → AggregateDevice → IOProc)
  └─ ProcessTapRecorder  → AVAudioFile → *.system.wav

AVAudioEngine (inputNode → MixerNode → tap)
  └─ MicrophoneCapture   → AVAudioFile → *.microphone.wav

↑ 両ストリームは AudioRecordingCoordinator が同期起動・停止
```

2つのストリームは最後まで分離されたまま文字起こしレイヤーに渡される。

---

### 型・設定・状態

**`RecordingConfiguration`** (`RecordingConfiguration.swift:1–23`)

```swift
struct RecordingConfiguration {
    let id: String
    let audioProcess: AudioProcess      // objectID + name
    let enableMicrophone: Bool
    let baseURL: URL                    // 拡張子なしのベース URL

    var expectedFiles: RecordedFiles {
        // baseURL.appendingPathExtension("microphone.wav")
        // baseURL.appendingPathExtension("system.wav")
    }
}
```

`appendingPathExtension("microphone.wav")` の挙動に注意。結果は `id_timestamp.microphone.wav`（ドット2段）になる。

**`RecordingState`** (`RecordingState.swift:1–8`)

```swift
enum RecordingState {
    case idle
    case starting
    case recording(AudioRecordingCoordinatorType)  // コーディネータを直保持
    case stopping
    case failed(Error)
}
```

`.recording` ケースにコーディネータの参照を持たせることで、`stop()` の呼び出しを enum の pattern match 経由に統一している。

---

### ProcessTap — システム音声キャプチャの土台

macOS 14.2+ の `AudioHardwareCreateProcessTap` を使い、特定プロセスの音声を Aggregate Device 経由でタップする。

**Aggregate Device 構築の核心** (`ProcessTap.swift:96–148`):

```swift
let tapDescription = CATapDescription(stereoMixdownOfProcesses: [objectID])
tapDescription.uuid = UUID()
tapDescription.muteBehavior = .unmuted   // または .mutedWhenTapped

AudioHardwareCreateProcessTap(tapDescription, &tapID)

// kAudioAggregateDeviceIsPrivateKey: true は必須（省略するとシステム出力一覧に露出）
// kAudioAggregateDeviceTapAutoStartKey: true
// kAudioSubTapDriftCompensationKey: true（ドリフト補正）
AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
```

`tapStreamDescription` は `AudioHardwareCreateAggregateDevice` の**前**に `tapID.readAudioTapStreamBasicDescription()` で取得している（:139行）。これによりマイク側の `targetFormat` として渡せる。

**IOProc コールバックでのゼロコピー書き込み** (`ProcessTap.swift:237–254`):

```swift
try tap.run(on: queue) { inNow, inInputData, inInputTime, outOutputData, inOutputTime in
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                        bufferListNoCopy: inInputData,
                                        deallocator: nil) else { return }
    try currentFile.write(from: buffer)
    self.updateAudioLevel(from: buffer)
} invalidationHandler: { ... }
```

**AVAudioFile 設定**:

```swift
// tap のネイティブフォーマット値をそのまま使用
let settings: [String: Any] = [
    AVFormatIDKey: streamDescription.mFormatID,
    AVSampleRateKey: format.sampleRate,
    AVNumberOfChannelsKey: format.channelCount,
]
let file = try AVAudioFile(forWriting: fileURL, settings: settings,
                           commonFormat: .pcmFormatFloat32,
                           interleaved: format.isInterleaved)
```

**システム音声レベルメータ** (`ProcessTap.swift:278–303`): ピーク絶対値を dBFS 変換 → 0–1 正規化。

```swift
let decibels = 20 * log10(max(maxLevel, 0.00001))  // アンダーフロー防止
let normalizedLevel = (decibels + 60) / 60          // -60dBFS=0, 0dBFS=1.0
Task { @MainActor in self._tap?.setAudioLevel(min(max(normalizedLevel, 0), 1)) }
```

---

### MicrophoneCapture — AVAudioEngine によるマイク録音

**pre-warm 機構**: `init()` で即座にバックグラウンド Task を起動して AVAudioEngine を事前準備する。`start()` 呼び出し時には最大 100ms のスピンウェイトで完了を待つ（後述の移植注意参照）。

**フォーマットチェーン**: inputNode → MixerNode → tap を全区間同一フォーマットで接続し、エンジングラフ上では変換を挟まない (`MicrophoneCapture+AudioEngine.swift:22–49`)。

```swift
engine.connect(inputNode, to: mixerNode, format: inputFormat)
converterNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { ... }
```

サンプルレート変換は tap コールバック内で `AVAudioConverter` を使ってオンザフライで行う:

```swift
let frameCapacity = AVAudioFrameCount(
    Double(inputBuffer.frameLength) * (targetFormat.sampleRate / inputBuffer.format.sampleRate)
)
converter.convert(to: outputBuffer, error: &error) { _, outStatus in
    outStatus.pointee = .haveData; return inputBuffer
}
```

**マイクレベルメータ** (`MicrophoneCapture+AudioProcessing.swift:57–74`): ch0 の平均絶対値 × 10。

```swift
let average = sum / Float(frameCount)
let level = min(average * 10, 1.0)
DispatchQueue.main.async { self?.audioLevel = level }
```

**システム音声（dBFS ピーク）とマイク（平均絶対値）は算出方式が異なる**。UI で2本のメータを並べる場合、縮尺が揃わない。sokki で統一するなら両方 dBFS ピークに揃えることを推奨。

---

### AudioRecordingCoordinator — デュアル同期起動

起動順序に依存関係がある (`AudioRecordingCoordinator.swift:25–56`):

```swift
// 1. システム音声を先に起動
try await MainActor.run { try recorder.start() }

// 2. tapStreamDescription が確定してからマイクを起動
await MainActor.run { processTap.activate() }
guard let tapStreamDescription = processTap.tapStreamDescription else { throw ... }
try microphoneCapture.start(outputURL: microphoneURL, targetFormat: tapStreamDescription)
```

マイクの `targetFormat` は ProcessTapRecorder 起動後でないと取得できない。順序を逆転すると `nil` になる。

**stop() の順序** (`AudioRecordingCoordinator.swift:58–69`):

```swift
microphoneCapture?.stop()    // 1. マイク
tapRecorder?.stop()           // 2. システム音声（内部で tap.invalidate() 呼ぶ）
processTap.invalidate()       // 3. tap リソース解放
```

---

### RecordingSessionManager — セッション工場

```swift
func startSession(configuration: RecordingConfiguration) async throws -> AudioRecordingCoordinatorType {
    let processTap = ProcessTap(process: configuration.audioProcess)
    await MainActor.run { processTap.activate() }
    // マイク有効時のみパーミッションチェック
    // AudioRecordingCoordinator を生成して start() 呼び出し
}
```

---

### RecordingCoordinator — 最上位 ObservableObject

SwiftUI から `@StateObject` で参照。`RecordingState` を `private(set)` で保持し、`startRecording(configuration:)` が `.starting → .recording(coordinator)` に、`stopRecording()` が `.stopping → .idle` に遷移して `RecordedFiles` を返す。

**要約機能の独立性**: `RecordingCoordinator.stopRecording()` は `RecordedFiles`（URL のペア）を返すだけで、要約サービスを一切参照していない。要約コードを削除しても本章のコードは変更不要。

---

### RecordingFileManager — ファイル命名規則と保存先

```swift
// 保存先: FileManager.default.temporaryDirectory/Recordings/
// ファイル名: {recordingID}_{unixtime}.system.wav
//             {recordingID}_{unixtime}.microphone.wav
```

**sokki との差異**: Recap は `/tmp` 相当に書く（再起動で消える）。sokki では Issue #4 の通り `.m4a` 形式でアプリサポートディレクトリに永続保存すること。WAV → M4A に変える場合は `AVFormatIDKey: kAudioFormatMPEG4AAC` に変更し `AVEncoderBitRateKey` を追加する。

---

### 移植時の勘所まとめ

| # | 項目 | 内容 |
|---|------|------|
| 1 | **actor 境界** | `AVAudioFile` は `Sendable` 非準拠。IOProc の queue を固定し、MainActor をまたがない設計を維持すること |
| 2 | **pre-warm スピンウェイト除去** | `usleep` ループ → `await preparationTask?.value` に置き換えてノンブロッキング化 |
| 3 | **macOS 14.2+ 専用 API** | `CATapDescription`、`AudioHardwareCreateProcessTap` は macOS 14.2+。sokki の最低ターゲット macOS 15 なら問題なし |
| 4 | **SwiftData との統合** | 録音レイヤーは SwiftData を一切使わない。`RecordedFiles` の URL を受け取った後に `@Model` に保存する構造が自然。`@Model` クラスを録音スレッドに渡さないこと |
| 5 | **SwiftPM** | `SokkiKit` ターゲットの `Package.swift` に `AudioToolbox`、`AVFoundation`、`AudioUnit` のリンクを追加 |
| 6 | **@Observable への移行** | `@Published var audioLevel` → `var audioLevel: Float = 0.0`（`@Observable` マクロ管理）に変更、プロトコルから `ObservableObject` 準拠を削除 |
| 7 | **要約は省略可能** | 録音レイヤーは要約サービスを一切 import・参照していない。そのまま利用可能 |

### 必要な Entitlements

- `com.apple.security.device.audio-input`: `true`（マイク使用）
- `com.apple.security.device.microphone`: `true`（TCC ダイアログ表示用）
- Hardened Runtime の Audio Input チェック（公証時）
- `Info.plist` の `NSMicrophoneUsageDescription`（省略するとクラッシュ）
- `AudioHardwareCreateProcessTap` は現時点で追加 entitlement 不要だが、Apple の方針変更に注意


<!-- ===== extract: transcription ===== -->

これで全ファイルの読み取りが完了しました。設計ドキュメントを作成します。

## 文字起こしサブシステム — WhisperKit 連携・モデル管理

### 1. サブシステム全体像

Recap の文字起こしサブシステムは以下の4層で構成される。

```
WhisperModelsView (SwiftUI)
  └─ WhisperModelsViewModel (@MainActor ObservableObject)
       └─ WhisperModelRepository (Core Data 永続化)
            ↕
       TranscriptionService (@MainActor)
            └─ WhisperKit (WhisperKit+ProgressTracking 拡張経由)
```

---

### 2. WhisperKit の生成 — `createWithProgress`

`WhisperKit+ProgressTracking.swift` に `WhisperKit` への `extension` として実装されている独自ファクトリ関数。WhisperKit 本体の Progress 通知が外部コールバックを持たないため、**ダウンロードと初期化を分離**して進捗を取得している。

```swift
// WhisperKit+ProgressTracking.swift:45-90
static func createWithProgress(
    model: String?,
    downloadBase: URL? = nil,
    modelRepo: String? = nil,
    modelToken: String? = nil,   // HF_TOKEN に相当
    modelFolder: String? = nil,
    download: Bool = true,
    progressCallback: @escaping (Progress) -> Void
) async throws -> WhisperKit {
    // 1. WhisperKit.download() でモデルファイルをキャッシュに落とし、
    //    そのフォルダパスを取得
    let downloadedFolder = try await WhisperKit.download(
        variant: modelVariant,
        from: repo,
        token: modelToken,
        progressCallback: progressCallback   // ここで進捗コールバックが機能
    )
    // 2. download: false で WhisperKit を初期化（再DLしない）
    let config = WhisperKitConfig(
        model: model, modelFolder: actualModelFolder, download: false
    )
    return try await WhisperKit(config)
}
```

**重点ポイント:**
- `modelRepo` は常に `"argmaxinc/whisperkit-coreml"` が渡される。
- `modelToken` は引数シグネチャにあるが、`TranscriptionService.loadModel()` では**渡していない**（`nil`）。つまり Recap は HF_TOKEN を使用せず、パブリックリポジトリのみを対象としている。HF_TOKEN が必要な Private モデルには非対応の実装。
- `progressCallback` は `@escaping (Progress) -> Void`。`Progress.fractionCompleted` を UI に渡す。

#### モデルサイズ情報の取得

```swift
// WhisperKit+ProgressTracking.swift:15-43
static func getModelSizeInfo(for modelName: String) async -> ModelSizeInfo {
    let hubApi = HubApi()
    let repo = Hub.Repo(id: "argmaxinc/whisperkit-coreml", type: .models)
    let fileMetadata = try await hubApi.getFileMetadata(from: repo, matching: ["*\(modelName)*/*"])
    // totalSizeMB = sum(metadata.size) / 1024 / 1024
}
```

`Hub` フレームワーク（`huggingface-swift`）の `HubApi` を直接利用。失敗時のフォールバックサイズ一覧も内包している（tiny=218MB, small=1342MB, medium=2917MB, large-v3=16793MB など）。

---

### 3. TranscriptionService

**シグネチャ（`TranscriptionServiceType` プロトコル）:**

```swift
// TranscriptionServiceType.swift:3-8
@MainActor
protocol TranscriptionServiceType {
    func transcribe(audioURL: URL, microphoneURL: URL?) async throws -> TranscriptionResult
    func ensureModelLoaded() async throws
    func getCurrentModel() async -> String?
}
```

**`TranscriptionResult` 構造体:**

| プロパティ | 型 | 内容 |
|---|---|---|
| `systemAudioText` | `String` | システム音声の文字起こし結果 |
| `microphoneText` | `String?` | マイク音声の文字起こし結果（任意） |
| `combinedText` | `String` | 上記を結合したテキスト（要約プロンプト用） |
| `transcriptionDuration` | `TimeInterval` | 処理時間 |
| `modelUsed` | `String` | 使用モデル名 |

**`transcribe(audioURL:microphoneURL:)` の制御フロー:**

```
1. audioURL の存在確認（なければ .audioFileNotFound）
2. ensureModelLoaded() → 選択モデルと loadedModelName の差異チェック
3. transcribeAudioFile(systemAudioURL)  ← whisperKit.transcribe(audioPath:)
4. microphoneURL があれば transcribeAudioFile(microphoneURL)
5. buildCombinedText() で2つを結合
6. TranscriptionResult を返す
```

**`whisperKit.transcribe(audioPath:)` の呼び出しと結果の組み立て:**

```swift
// TranscriptionService.swift:93-107
let transcriptionResults = try await whisperKit.transcribe(audioPath: url.path)
let text = transcriptionResults
    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    .joined(separator: " ")
```

- 戻り値は `[TranscriptionResult]`（WhisperKit 型）。各要素の `.text` を trim→filter→join でフラットな `String` に変換する。
- **segment ごとのタイムスタンプや話者情報は一切使っていない**。

**システム音声とマイク音声の結合方法:**

```swift
// TranscriptionService.swift:109-118
private func buildCombinedText(systemAudioText: String, microphoneText: String?) -> String {
    var combinedText = systemAudioText
    if let microphoneText, !microphoneText.isEmpty {
        combinedText += "\n\n[User Audio Note: ...]"
        combinedText += microphoneText
        combinedText += "\n\n[End of User Audio Note. ...]"
    }
    return combinedText
}
```

`combinedText` はシステム音声テキストを先頭に置き、マイクテキストを「`[User Audio Note: ...]`」ブロックとして末尾に追記する単純な文字列連結。**このブロックは LLM 要約プロンプトへの注入を目的としており、sokki では要約を採用しないため `combinedText` フィールドは不要または簡略化可能**（後述）。

**モデルの遅延ロードとキャッシュ:**

```swift
// TranscriptionService.swift:52-62
func ensureModelLoaded() async throws {
    let selectedModel = try await whisperModelRepository.getSelectedModel()
    guard let model = selectedModel else { throw .modelNotAvailable }
    if loadedModelName != model.name || whisperKit == nil {
        try await loadModel(model.name, isDownloaded: model.isDownloaded)
    }
}
```

`loadedModelName` との差分比較でリロードを抑制。モデルロード後に `isDownloaded == false` であれば `markAsDownloaded()` を呼んで DB を更新する（DL済み状態の後付け修正）。

---

### 4. WhisperModelRepository — Core Data による永続化

`WhisperModel` は Core Data の `NSManagedObject` サブクラス。プロパティは以下。

| プロパティ | Core Data 型 | 内容 |
|---|---|---|
| `name` | String? | モデル名 (`"tiny"`, `"small"` 等) |
| `isDownloaded` | Bool | DL 完了フラグ |
| `isSelected` | Bool | 選択中フラグ |
| `downloadedAt` | Int64 | `Date.timeIntervalSince1970` を整数で保存 |
| `fileSizeInMB` | Int64 | モデルサイズ (MB) |
| `variant` | String? | バリアント文字列（任意） |

**`setSelectedModel(name:)` の実装パターン:**

```swift
// WhisperModelRepository.swift:85-102
// 1. 全モデルの isSelected を false に
deselectRequest.predicate = NSPredicate(format: "isSelected == YES")
selectedModels.forEach { $0.isSelected = false }
// 2. ダウンロード済みのものだけを選択可能に
selectRequest.predicate = NSPredicate(format: "name == %@ AND isDownloaded == YES", name)
modelToSelect.isSelected = true
try coreDataManager.save()
```

「ダウンロード済みでないモデルは選択不可」というバリデーションがリポジトリ層に入っている。

**`WhisperModelData` 転送型:**

```swift
struct WhisperModelData: Equatable {
    let name: String
    var isDownloaded: Bool
    var isSelected: Bool
    var downloadedAt: Date?
    var fileSizeInMB: Int64?
    var variant: String?
}
```

Core Data の `WhisperModel` オブジェクトはコンテキスト外に持ち出さず、`mapToData()` で `WhisperModelData`（純粋な値型）に変換してから外部に渡すパターンを徹底している。

---

### 5. WhisperModelsViewModel — DL 進捗管理の状態機械

**公開プロパティ（`@Published`）:**

| プロパティ | 型 | 役割 |
|---|---|---|
| `selectedModel` | `String?` | 選択中モデル名 |
| `downloadedModels` | `Set<String>` | DL 済みモデル名セット |
| `downloadingModels` | `Set<String>` | DL 中モデル名セット |
| `downloadProgress` | `[String: Double]` | モデル名 → 進捗率 (0.0〜1.0) |
| `errorMessage` | `String?` | エラーメッセージ |

**ダウンロードフロー（`downloadModel(_:)`）:**

```swift
// WhisperModelsViewModel.swift:59-93
func downloadModel(_ modelName: String) {
    Task {
        downloadingModels.insert(modelName)
        downloadProgress[modelName] = 0.0
        _ = try await WhisperKit.createWithProgress(
            model: modelName,
            modelRepo: "argmaxinc/whisperkit-coreml",
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress[modelName] = progress.fractionCompleted
                }
            }
        )
        // DL後にサイズ情報を取得して DB に書き込み
        let modelInfo = await WhisperKit.getModelSizeInfo(for: modelName)
        try await repository.markAsDownloaded(name: modelName, sizeInMB: Int64(modelInfo.totalSizeMB))
        downloadedModels.insert(modelName)
        downloadingModels.remove(modelName)
    }
}
```

`progressCallback` 内で `Task { @MainActor in ... }` を使って UI スレッドに切り替えている。`[weak self]` で循環参照を回避。

**モデルリスト分類:** WhisperKit の `ModelVariant.multilingualCases` を列挙し、`isRecommended`（large-v3, medium, small）とその他に分類して表示する。英語専用の `en` バリアントは `filter { $0.isMultilingual }` で除外している。

---

### 6. entitlements

HF_TOKEN を使用しないため Keychain アクセス権限は不要。ただし：

- **ネットワークアクセス**: モデルのダウンロードに `com.apple.security.network.client` entitlement が必要（サンドボックスアプリの場合）。
- **ファイルシステムアクセス**: WhisperKit はモデルファイルを Application Support 配下のキャッシュディレクトリ（`~/Library/Application Support/huggingface/models/argmaxinc/whisperkit-coreml/`）に保存する。サンドボックス環境では自動的に自アプリのコンテナ内に制限されるため追加権限は不要。

---

### 7. sokki への移植時の勘所

#### Core Data → SwiftData 置き換え

Recap の `WhisperModelRepository` は全面的に Core Data（`NSManagedObjectContext`, `NSFetchRequest`, `NSPredicate`）に依存している。sokki は SwiftData を使うため、以下の対応が必要。

```swift
// sokki での SwiftData モデル定義（例）
@Model
final class WhisperModelRecord {
    var name: String
    var isDownloaded: Bool
    var isSelected: Bool
    var downloadedAt: Date?
    var fileSizeInMB: Int64
    var variant: String?
    
    init(name: String, ...) { ... }
}
```

- `NSPredicate` → `#Predicate<WhisperModelRecord>` に書き換え。
- `setSelectedModel` の「全件 deselect + 1件 select」は SwiftData の `FetchDescriptor` + ループで同等実装。
- `mapToData()` パターン（`NSManagedObject` を値型に変換）は SwiftData では `@Model` クラスをそのまま渡すことも可能だが、**actor 境界をまたぐ場合は `PersistentIdentifier` 経由**にする（`CLAUDE.md` の注意事項に準拠）。

#### `@MainActor` 境界の一貫性

Recap は `TranscriptionService`, `WhisperModelRepository`, `WhisperModelsViewModel` をすべて `@MainActor` で宣言しており、actor 境界の問題を回避している。sokki でも同じアプローチを踏襲するのが最短路。`async/await` チェーン全体を MainActor に閉じ込めることで `Sendable` 違反を避けられる。

ただし WhisperKit の推論（`transcribe(audioPath:)`）は CPU/GPU 集中処理のため、**MainActor をブロックする**点に注意。Recap はこれを許容している。sokki で UI の応答性を優先するなら `Task.detached` や `nonisolated` メソッドへの切り出しを検討すること。

#### `progressCallback` の Sendable 問題

`createWithProgress` の `progressCallback: @escaping (Progress) -> Void` は Sendable 要求を受ける可能性がある（Swift 6 strict concurrency）。Recap は `Task { @MainActor in ... }` で対処しており、sokki でも同じパターンを使う。

#### `WhisperKit+ProgressTracking.swift` はそのまま流用可能

この `extension WhisperKit` ファイルは `Foundation`, `WhisperKit`, `Hub` のみに依存し、Core Data も SwiftData も参照していない。**ほぼそのままコピーして使える**。`Hub` フレームワークが `Package.swift` の依存に含まれているか確認が必要（WhisperKit が依存するため通常は自動的に解決される）。

#### `combinedText` と要約関連の整理

`buildCombinedText()` が生成する `[User Audio Note: ...]` ブロックは LLM 要約プロンプトへの注入専用テキストであり、**sokki では要約機能を採用しないためこのメソッドは省略可能**。`TranscriptionResult` の `combinedText` フィールドも不要。

残す必要があるのは：
- `systemAudioText` → メインの文字起こし本文として使用
- `microphoneText` → 話者分離の補助情報として使用するなら残す（不要なら削除）

マイク音声の独立した文字起こしを行うかどうかは録音アーキテクチャ（AVAudioEngine の単一ストリームか2トラック録音か）に依存する。Recap はシステム音声とマイクを別ファイルに録音して個別に `transcribe()` を呼ぶ設計だが、sokki が単一 AVAudioEngine ストリームのみを使う場合は `microphoneURL` 引数を削除して簡略化できる。

#### モデルリストの取得元

`WhisperModelsViewModel` は `ModelVariant.allCases`（WhisperKit 提供の enum）を列挙してリストを生成している。モデルリストをハードコードしているわけではなく、**WhisperKit の SDK バージョンアップで自動的に増減する**。sok​ki でも同じアプローチを推奨する。


<!-- ===== extract: meeting-detection ===== -->

以下が抽出した設計ドキュメント本文（Artifact 版も同内容）です。

---

## 1. アーキテクチャ概観

Recap の会議自動検出は **3 層**で構成される。最上位の `MeetingDetectionService` が 1 秒間隔でポーリングし、`SCShareableContent.current` でウィンドウ一覧を取得して各 Detector へ渡す。Detector はウィンドウタイトルを `MeetingPatternMatcher` に通し、confidence 付きの結果を返す。Service は最高 confidence の結果を `MeetingState` として Combine で流し、ViewModel が録音自動開始の連携を行う。

```
MeetingDetectionService (@MainActor, 1s ポーリング)
  ↓ SCShareableContent.current → content.windows
TeamsMeetingDetector / ZoomMeetingDetector / GoogleMeetDetector
  ↓ MeetingPatternMatcher.findBestMatch(in: title)
MeetingDetectionResult { isActive, title, confidence(.high|.medium|.low) }
  ↓ meetingStatePublisher: AnyPublisher<MeetingState, Never>
RecapViewModel+MeetingDetection (録音通知 / AudioProcess 自動選択)
```

---

## 2. MeetingDetectionService — コアポーリングループ

**シグネチャ（`MeetingDetectionService.swift`）:**

```swift
@MainActor
final class MeetingDetectionService: MeetingDetectionServiceType {
    @Published private(set) var isMeetingActive: Bool
    @Published private(set) var activeMeetingInfo: ActiveMeetingInfo?
    @Published private(set) var detectedMeetingApp: AudioProcess?
    @Published private(set) var hasPermission: Bool
    @Published private(set) var isMonitoring: Bool
    var meetingStatePublisher: AnyPublisher<MeetingState, Never>
    func startMonitoring()
    func stopMonitoring()
    private let checkInterval: TimeInterval = 1.0  // ハードコード
}
```

**ポーリングループ（`L53–65`）:**

```swift
// Timer や RunLoop は使わず Task.sleep ベース
monitoringTask = Task {
    while !Task.isCancelled {
        await checkForMeetings()
        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000))
    }
}
```

**ウィンドウフィルタと confidence 最大値選択（`L75–125`）:**

```swift
let content = try await SCShareableContent.current  // 失敗→ hasPermission = false
for detector in detectors {
    let relevantWindows = content.windows.filter {
        detector.supportedBundleIdentifiers.contains($0.owningApplication?.bundleIdentifier ?? "")
    }
    if !relevantWindows.isEmpty {
        let result = await detector.checkForMeeting(in: relevantWindows)
        // result.confidence.rawValue (high=3, medium=2, low=1) で最大を選択
    }
}
```

`SCShareableContent.current` の throw が権限拒否の検知を兼ねており、別途 `CGPreflightScreenCaptureAccess()` を呼ぶ必要はない。

**`meetingStatePublisher`** は `Publishers.CombineLatest3` + `.removeDuplicates()` で構成される。`MeetingState` の `Equatable` は `appName + title` の文字列比較のみ。

---

## 3. 各 Detector の supportedBundleIdentifiers とパターン

| Detector | supportedBundleIdentifiers | 代表パターン |
|---|---|---|
| ZoomMeetingDetector | `us.zoom.xos` | `zoom meeting`(high), `zoom webinar`(high), `screen share`(medium) |
| TeamsMeetingDetector | `com.microsoft.teams`, `com.microsoft.teams2` | `| Microsoft Teams`(high, caseSensitive, excludePatterns: chat/activity), `call with`(high) |
| GoogleMeetDetector | Chrome / Safari / Firefox / Edge | `meet.google.com`(high), `google meet`(high), `meet -`(medium) |

3 Detector すべてに `commonMeetingPatterns`（`refinement`/`daily`/`sync`/`retro`/`meeting`/`call`）が追加される。bundleID フィルタ後のウィンドウにのみ適用されるため、ブラウザで偶然 "meeting" という単語のタブを開いているだけでは誤検知しない。

**`MeetingDetectorType` プロトコル（`MeetingDetectorType.swift:19–26`）:**

```swift
@MainActor
protocol MeetingDetectorType: ObservableObject {
    var isMeetingActive: Bool { get }
    var meetingTitle: String? { get }
    var meetingAppName: String { get }
    var supportedBundleIdentifiers: Set<String> { get }
    func checkForMeeting(in windows: [any WindowTitleProviding]) async -> MeetingDetectionResult
}
```

引数の `[any WindowTitleProviding]` は `SCWindow` に対するテスト用プロトコルラッパー。`extension SCWindow: WindowTitleProviding {}` で適合。

---

## 4. MeetingPatternMatcher — パターン照合ロジック

```swift
struct MeetingPattern {
    let keyword: String
    let confidence: MeetingDetectionResult.MeetingConfidence
    let caseSensitive: Bool      // デフォルト false
    let excludePatterns: [String] // デフォルト []
}
```

**`findBestMatch` のアルゴリズム（`L22–48`）:**

- `init` で confidence 降順にソート済み → 最高 confidence のパターンから線形走査
- `caseSensitive: false` の場合は `title.lowercased()` に対して `keyword.lowercased()` で `contains`
- `excludePatterns` にヒットした場合は skip（Teams の chat/activity タブ除外に使用）
- **正規表現不使用**、`String.contains` 部分一致のみ

---

## 5. AudioProcess モデルと meetingAppBundleIDs

`AudioProcess` は `Identifiable, Hashable, Sendable` な struct で `AudioObjectID` をラップする。`isMeetingApp` は computed property で 11 アプリの静的 Set（Zoom/Teams/Slack/Chrome/Webex/GoTo/RingCentral/Skype/Discord/Around）と照合する。

**Detector の `supportedBundleIdentifiers` とは独立管理**。Detector 側は SCWindow フィルタ用、`meetingAppBundleIDs` は AudioToolbox プロセス絞り込み用（`AudioProcessController.meetingApps`）。追加時は両方の更新が必要になるケースがある。

`AudioProcessController` は `NSWorkspace.shared.publisher(for: \.runningApplications)` を Combine で購読し、起動/終了のたびに AudioToolbox の `AudioObjectID.readProcessList()` で `[AudioProcess]` を再構築する。

---

## 6. ViewModel との連携

検出→録音は**通知ベース**であり、検出と同時に録音が走るわけではない。

```swift
func handleMeetingDetected(info: ActiveMeetingInfo, detectedApp: AudioProcess?) {
    autoSelectAppIfAvailable(detectedApp)  // AudioProcess を録音対象に自動セット
    let key = "\(info.appName)-\(info.title)"
    if lastNotifiedMeetingKey != key {
        lastNotifiedMeetingKey = key
        sendMeetingStartedNotification(appName:title:)  // 通知送信のみ
    }
}
```

`lastNotifiedMeetingKey` で同一会議への重複通知を防ぐ。`sendMeetingEndedNotification` は現在 `// TODO` の空実装。

---

## 7. 権限と Entitlements

`Recap.entitlements` に Screen Capture 専用キーはない。`SCShareableContent.current` が throw した時点で権限拒否を検知する設計。必要な entitlements は `com.apple.security.app-sandbox`、`com.apple.security.device.audio-input`、`com.apple.security.network.client`（WhisperKit モデルダウンロード）。

---

## 8. 要約機能との依存関係

**会議自動検出サブシステムは要約機能に一切依存しない。** 検出→状態通知→録音開始の連携は完全に独立しており、要約処理（`ProcessingCoordinator`/`SummarizationService`）は録音終了後の別パイプライン。要約を省略しても `MeetingDetectionService` および各 Detector は完全動作する。

---

## 9. 移植時の勘所

**`@Observable` マクロへの変換**
Recap は `ObservableObject + @Published` ベース。sokki で `@Observable` を採用する場合、`@Published private(set) var` を `private(set) var` に変換する。ただし `meetingStatePublisher` が Combine `AnyPublisher` を返すため、Combine 依存を維持するか `AsyncStream` に置き換えるかを先に決める必要がある。

**`@MainActor` 伝播**
`MeetingDetectionService`、`MeetingDetectorType`、`AudioProcessController` はすべて `@MainActor`。このまま移植すれば actor 境界問題は発生しない。`SCShareableContent.current` は非 UI スレッドでも呼べるが、結果の書き戻しはメインアクターで行う必要があり、現行設計はこれを満たしている。

**AudioProcess と SwiftData**
`AudioProcess` は `@Model` にする必要はない（runtime-only な値）。録音セッションに「どの会議アプリで検出されたか」を永続化したい場合は `bundleID: String?` と `appName: String` を `@Model` クラスの通常プロパティとして別途持つ方が安全。

**AudioToolbox の依存**
`AudioObjectID.readProcessList()` は AudioToolbox 低レベル API のラッパー。SwiftPM ターゲットの `project.yml` に `sdk: AudioToolbox.framework` を追加しないとリンクエラーになる。

**`NSImage` の Sendable 問題**
`AudioProcess` は `Sendable` 適合済みだが、`icon: NSImage` プロパティは `Sendable` でない。actor 境界を越えて渡す場合は `icon` を遅延取得か `nonisolated` で外出しにすること。

**Google Meet 誤検知リスク**
4 ブラウザすべてがフィルタ対象のため、`meet.google.com` を含む URL をどこかのタブで開いていると検出される。sokki では `meet.google.com`(high) のみ残し、`meet -`(medium) などを削除するか、ユーザー設定でオフにできる構造にすることを推奨する。

**そのままコピーできるファイル:** `MeetingPatternMatcher.swift`、`MeetingPattern`、3 Detector のパターン定義、`MeetingDetectionResult`、`ActiveMeetingInfo`、`MeetingState`、`PermissionsHelper.swift` は依存なしの純粋 Swift コード。


<!-- ===== extract: pipeline-di-persistence ===== -->

設計ドキュメントをアーティファクトに公開しました。以下が本文の内容です（アーティファクトと同内容）。

---

## 処理パイプライン概要

録音停止から最終保存まで、`ProcessingCoordinator`（`@MainActor final class`）が全フェーズを直列オーケストレーションする。すべての状態変更と UI 通知がメインスレッドで完結する設計になっている。

状態遷移は `.recording → .transcribing → .transcribed → (.summarizing) → .completed` で、要約フェーズはゲートされており、`autoSummarizeEnabled == false` の場合は `.transcribed` から直接 `.completed` へ進む。

## AsyncStream キュー実装

`AsyncStream.makeStream()` で `(stream, continuation)` のペアを生成し、録音ジョブを直列消化する。

```swift
// ProcessingCoordinator.swift : 17–18
private let processingQueue = AsyncStream<RecordingInfo>.makeStream()

// 投入
func startProcessing(recordingInfo: RecordingInfo) async {
    processingQueue.continuation.yield(recordingInfo)
}

// 消化ループ（init で起動）
queueTask = Task {
    for await recording in processingQueue.stream {
        guard !Task.isCancelled else { break }
        currentProcessingState = .processing(recordingID: recording.id)
        processingTask = Task { await processRecording(recording) }
        await processingTask?.value   // 完了を待ってから次へ
        currentProcessingState = .idle
    }
}
```

直列保証は `await processingTask?.value` で実現。バッファポリシーはデフォルト `.unbounded`。

## 状態モデル

状態は2層。コーディネーター自身の処理状態（`ProcessingState`）と DB に永続化される録音ステップ状態（`RecordingProcessingState`）は別 enum で管理される。

```swift
// ProcessingState.swift — コーディネーター状態
enum ProcessingState: Equatable {
    case idle
    case processing(recordingID: String)
    case paused(recordingID: String)  // スリープ中
}

// RecordingProcessingState.swift — DB 永続化状態（Int16 rawValue）
enum RecordingProcessingState: Int16, CaseIterable {
    case recording = 0, recorded = 1, transcribing = 2, transcribed = 3
    case summarizing = 4       // sokki では不要
    case completed = 5
    case transcriptionFailed = 6
    case summarizationFailed = 7   // sokki では不要
}
```

## Task キャンセル設計

`queueTask`（長命）と `processingTask`（録音単位）を別 `Task` で保持し個別キャンセルを可能にしている。キャンセル時は DB を `.recorded` に巻き戻す。WhisperKit 自体がキャンセルを伝播しないため、`performTranscriptionPhase` の直後に `Task.isCancelled` を手動チェックする協調的キャンセルのポイントが置かれている。

## スリープ・復帰対応

`SystemLifecycleManager` が `NSWorkspace.willSleepNotification` / `didWakeNotification` を購読し `SystemLifecycleDelegate` 経由で通知。スリープ時は `processingTask?.cancel()` して `.paused` 状態へ移行。復帰時は DB から最新 `RecordingInfo` を再取得してキューに再投入するため、スリープ中の状態変更にも整合する。

## 要約フェーズ — 省略しても成立することの確認

**省略しても文字起こし＋保存パスは成立する**。`completeProcessingWithoutSummary` は `summaryText: ""` で完了を通知するパスとして既存実装内にある。

| 削除対象 | 対応 |
|---|---|
| `performSummarizationPhase` | 分岐ごと削除、`completeProcessing` を無条件呼び出しに |
| `checkAutoSummarizeEnabled` | 削除、`userPreferencesRepository` 依存も除去可能 |
| `summarizationService` プロパティ | init パラメーターから削除 |
| `summaryText` フィールド | SwiftData モデルに含めないか `nil` 許容で残す |
| `ProcessingError.summarizationFailed` | switch が exhaustive になることを確認してから削除 |
| `RecordingProcessingState.summarizing/summarizationFailed` | 値 4, 7 を欠番にするか enum から削除して migration guard を書く |

## DI コンテナ — 構成パターン

手製 Service Locator。`@MainActor final class DependencyContainer` が全依存を `lazy var` で遅延初期化し、ファイルを役割ごとに extension 分割している。

- **本体**: `lazy var` プロパティ宣言と公開ファクトリメソッド
- `+Services.swift`: TranscriptionService, SummarizationService 等の make*
- `+Repositories.swift`: RecordingRepository, UserPreferencesRepository 等の make*
- `+Coordinators.swift`: ProcessingCoordinator, RecordingCoordinator の make*
- `+Managers.swift`: CoreDataManager, RecordingFileManager 等の make*
- `+ViewModels.swift`: 各 ViewModel の make*

テスト・Preview は `DependencyContainer(inMemory: true)` で in-memory ストアに切り替わる。

## Core Data エンティティ構成

`RecapDataModel.xcdatamodel` に4エンティティ。

- **UserRecording**: 録音本体。`state` は `Int16` rawValue で保存。`summaryText` は sokki では省略可能
- **WhisperModel**: モデルダウンロード管理（`name`, `variant`, `isDownloaded`, `isSelected`, `fileSizeInMB`, `downloadedAt`）
- **LLMModel**: 要約用 LLM 設定 → sokki では不要
- **UserPreferences**: オンボード済みフラグと設定保持。要約関連カラムを除いて移植

## Repository 層

全 DB 操作は `performBackgroundTask` + `withCheckedThrowingContinuation` で async/await に橋渡し。NSManagedObject をそのまま外に渡さず、クロージャ内で即 `RecordingInfo`（値型 DTO）に変換してから `continuation.resume` に渡すことで context 漏れを防いでいる。

## Core Data → SwiftData 移植マッピング

| Core Data (Recap) | SwiftData (sokki) | 注意点 |
|---|---|---|
| `NSPersistentContainer` | `ModelContainer` | DI コンテナへ注入 |
| `NSManagedObjectContext` | `ModelContext` | 基本メインスレッド |
| `NSManagedObject` サブクラス | `@Model class` | class 必須、struct 不可 |
| `NSFetchRequest` | `#Predicate` + `FetchDescriptor` | 型安全 |
| `performBackgroundTask` + continuation | なし（同期 fetch） | 大幅にシンプルになる |
| `NSBatchDeleteRequest` | ループで `context.delete` | batch delete API なし |
| `inMemory: true` | `ModelConfiguration(isStoredInMemoryOnly: true)` | DI 差し替えで対応 |

## 移植時の勘所

1. **actor 境界**: `@MainActor` クラス内の `Task { }` は Swift 6 strict concurrency で actor を引き継がない場合がある。`Task { @MainActor in … }` を明示する
2. **Sendable**: `@Model` クラスは非 Sendable。Repository は必ず `RecordingInfo` 値型に変換して返す（Recap の実装を踏襲）。CLAUDE.md に記載の通り `PersistentIdentifier` で actor 境界を跨ぐ
3. **deinit での Task キャンセル**: `@MainActor` クラスの `deinit` は任意スレッドで呼ばれる可能性。明示的な `tearDown()` メソッドを用意し `ScenePhase.background` 等で呼ぶ
4. **AsyncStream バッファ**: デフォルト `.unbounded` は連続録音でメモリを際限なく使う。`.bufferingNewest(1)` 等で絞るか投入前にチェックする
5. **SwiftData batch delete**: 件数が少なければ全件 fetch → ループ delete で実用上問題なし

## 必要な Entitlements

| Entitlement | 用途 |
|---|---|
| `com.apple.security.files.user-selected.read-write` | 録音ファイル保存・削除 |
| `NSMicrophoneUsageDescription` | AVAudioEngine |
| `com.apple.security.screen-capture` | Phase 2 SCStream（Phase 1 は不要） |
| `com.apple.security.app-sandbox` | macOS 配布必須 |
| `com.apple.security.network.client` | 要約 LLM API（sokki では不要） |

**Sandbox + 録音ファイルの注意**: App Sandbox 環境ではユーザー指定の外部フォルダへの書き込みに Security-Scoped Bookmark が必要。Recap はパスを文字列で DB に保存しているが、sokki では Bookmark Data に変換して保存することを推奨する。


<!-- ===== extract: ui-permissions-menubar ===== -->

以下が設計ドキュメントの本文です。Artifact にも同内容を公開しました。

---

## アプリ起動フロー / 依存性注入（DI）

Recap は `@main struct RecapApp: App` を宣言するが、`body` には `Settings { EmptyView() }` しか置かない。実際の起動処理は全て `AppDelegate` で行い、`@NSApplicationDelegateAdaptor` でブリッジしている。

```swift
// RecapApp.swift:28–35
func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
        dependencyContainer = DependencyContainer()
        panelManager = dependencyContainer?.createMenuBarPanelManager()
        UNUserNotificationCenter.current().delegate = self
    }
}
```

`UNUserNotificationCenter.delegate = self` により通知タップ時に `userInfo["action"] == "open_app"` を拾って `panelManager?.showMainPanel()` を呼ぶパターンが実装されている。sokki でもそのまま流用できる。

### DependencyContainer の構造

`@MainActor final class DependencyContainer` が全依存物を `lazy var` として保持する（`DependencyContainer+Services.swift` / `+ViewModels.swift` 等に分割）。

| プロパティ | 型 | 備考 |
|---|---|---|
| `coreDataManager` | `CoreDataManagerType` | sokki では `ModelContainer` / `ModelContext` に置換 |
| `keychainService` | `KeychainServiceType` | 翻訳 API キー保存用に重要 |
| `summarizationService` / `llmService` | 各 Type | **省略可**（sokki 不採用） |
| `createMenuBarPanelManager()` | `MenuBarPanelManager` | 全 ViewModel を組み上げて返す |

起動シーケンス: `RecapApp.init` → `AppDelegate.applicationDidFinishLaunching` → `DependencyContainer()` → `createMenuBarPanelManager()` （ここで `providerWarningCoordinator.startMonitoring()` を呼ぶ） → `StatusBarManager` → `NSStatusItem` 登録。ユーザーが初めてアイコンをクリックした時点で `UserPreferencesRepository` の `onboarded` フラグを非同期取得し、未オンボードなら `OnboardingPanel`、以降は `MainPanel` を生成する。

---

## メニューバー常駐

### StatusBarManager

`final class StatusBarManager: StatusBarManagerType`（非 `@MainActor`）。

```swift
// StatusBarManager.swift:21–29
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let button = statusItem?.button {
    button.image = NSImage(named: "barIcon")
    button.target = self
    button.action = #selector(handleButtonClick(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
}
```

右クリック → `NSMenu` コンテキストメニュー（Quit のみ）。左クリック → `delegate?.statusItemClicked()`。`StatusBarDelegate` は `statusItemClicked()` と `quitRequested()` の 2 メソッドのみ。`MenuBarPanelManager` がこのデリゲートを適合し、トグル表示/非表示を行う。

### SlidingPanel (NSPanel サブクラス)

重要な初期化フラグ:

```swift
// SlidingPanel.swift:14–17
super.init(
    contentRect: .zero,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered, defer: false
)
```

```swift
self.level = .popUpMenu          // 最前面
self.isOpaque = false
self.backgroundColor = .clear
self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
self.alphaValue = 0.0            // 初期は非表示
```

`canBecomeKey: true`・`canBecomeMain: false`。パネルの `contentView` は `NSVisualEffectView`（`.popover` / `.behindWindow` / `cornerRadius: 12`）と `NSHostingController.view` の二層スタックで、Auto Layout で 4 辺フル充填する。

外部クリック検知は `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` で行う。`frame.contains(NSEvent.mouseLocation)` が false なら `panelDelegate?.panelDidReceiveClickOutside()` を呼ぶ。

### PanelAnimator

```swift
// PanelAnimator.swift:7–9
private static let slideInDuration:  CFTimeInterval = 0.3
private static let slideOutDuration: CFTimeInterval = 0.2
private static let translateOffset:  CGFloat        = 50
```

`CABasicAnimation(keyPath: "transform.translation.x")` で画面右外（`panelWidth + 50pt`）からスライドイン。スライドイン: `cubic-bezier(0.25, 0.46, 0.45, 0.94)`（ease-out 系）、スライドアウト: `cubic-bezier(0.55, 0.06, 0.68, 0.19)`（ease-in 系）。完了後 completion クロージャで `isVisible` フラグを反転。

### MenuBarPanelManager の主要責務

`@MainActor final class MenuBarPanelManager: MenuBarPanelManagerType, ObservableObject`。

- `positionPanel(_:size:)` — `statusButton.window?.screen` でマルチディスプレイ対応。スクリーン右端から `panelOffset: 12pt`、メニューバー直下 `panelSpacing: 8pt` の位置に配置（`initialSize = CGSize(width: 485, height: 500)`）。
- `toggleSidePanel(...)` — 設定/サマリーなどサイドパネルを排他制御。他パネルを先に hide してから show。
- `panelDidReceiveClickOutside()` — メインとサイド全パネルを hide。
- オンボーディング完了後の遷移: `MenuBarPanelManager+Delegates.swift` で `OnboardingDelegate` を適合し、`onboardingDidComplete()` → slideOut → 新 MainPanel slideIn を全て非同期に実行する。

---

## 権限要求・entitlements・Info.plist

### PermissionsHelper

`@MainActor final class PermissionsHelper: PermissionsHelperType`。

```swift
// PermissionsHelper.swift:8–32
func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            continuation.resume(returning: granted)
        }
    }
}

func requestScreenRecordingPermission() async -> Bool {
    do { let _ = try await SCShareableContent.current; return true }
    catch { return false }
}

func requestNotificationPermission() async -> Bool {
    (try? await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
}

func checkMicrophonePermissionStatus() -> AVAuthorizationStatus {
    AVCaptureDevice.authorizationStatus(for: .audio)
}

func checkScreenRecordingPermission() -> Bool {
    CGPreflightScreenCaptureAccess()  // macOS 11+
}
```

`PermissionsHelperType` は `@MainActor protocol`。テスト時は `#if MOCKING @Mockable` マクロで自動モック生成。sokki でもプロトコル + `@MainActor` 設計をそのまま採用できる。

### entitlements と Info.plist

| entitlement キー | 用途 | sokki 要否 |
|---|---|---|
| `com.apple.security.app-sandbox` | サンドボックス | 必須 |
| `com.apple.security.device.audio-input` | マイク録音 | 必須 |
| `com.apple.security.files.user-selected.read-only` | ファイル選択 | 任意（エクスポート時） |
| `com.apple.security.network.client` | 翻訳 API | 必須 |
| `com.apple.security.screen-capture` | SCStream（Phase 2） | Phase 2 以降 |

**Recap に画面収録 entitlement は存在しない。** `SCShareableContent.current` はウィンドウタイトル列挙のみで画面キャプチャを行わないため、Sandbox 内で entitlement なしに呼び出せる。sokki が Phase 2 で SCStream を実装する際に追加する。

---

## UseCase 各 ViewModel

### RecapViewModel

`@MainActor final class RecapViewModel: ObservableObject`。

| `@Published` プロパティ | 型 | 説明 |
|---|---|---|
| `isRecording` | Bool | 録音中フラグ |
| `recordingDuration` | TimeInterval | 秒単位。1s Timer で +1 |
| `microphoneLevel` / `systemAudioLevel` | Float | 0.1s ポーリング |
| `isMicrophoneEnabled` | Bool | マイクオン/オフ切替 |
| `showErrorToast` | Bool | AlertToast ライブラリ使用 |
| `activeWarnings` | [WarningItem] | Combine で warningManager に bind |

`delegate: RecapViewModelDelegate`（weak）が画面遷移要求を MenuBarPanelManager に委譲する。`openSettings()` / `openView()` / `openPreviousRecaps()` の 3 メソッドが転送先。

### StartRecording フロー

```swift
// RecapViewModel+StartRecording.swift:5–34
func startRecording() async {
    syncRecordingStateWithCoordinator()          // 1. コーディネータと状態同期
    guard !isRecording, let selectedApp else { return }
    let recordingID = UUID().uuidString           // 2. ID 生成
    currentRecordingID = recordingID
    let config = try await createRecordingConfiguration(...)  // 3. ファイルパス決定
    let recordedFiles = try await recordingCoordinator.startRecording(configuration: config)  // 4. 委譲
    try await createRecordingEntity(...)          // 5. Repository にエンティティ作成
    updateRecordingUIState(started: true)         // 6. isRecording = true + タイマー開始
}
```

`RecordingConfiguration` は `(id:, audioProcess:, enableMicrophone:, baseURL:)` の 4 プロパティ。`RecordedFiles` は `(systemAudioURL:, microphoneURL:, applicationName:)` の URL ペア。

### StopRecording フロー

```swift
// RecapViewModel+StopRecording.swift:5–25
func stopRecording() async {
    stopTimers()
    if let recordedFiles = await recordingCoordinator.stopRecording() {
        try await recordingRepository.updateRecordingURLs(...)
        try await recordingRepository.updateRecordingEndDate(id:, endDate: Date())
        try await recordingRepository.updateRecordingState(id:, state: .recorded, ...)
        if let updatedRecording = try await recordingRepository.fetchRecording(id: recordingID) {
            await processingCoordinator.startProcessing(recordingInfo: updatedRecording)
        }
    }
    updateRecordingUIState(started: false)
    currentRecordingID = nil
}
```

停止後に即 `processingCoordinator.startProcessing()` を呼ぶ。ProcessingCoordinator は `processingDidComplete` / `processingDidFail` / `processingStateDidChange` をデリゲートコールバックする。**要約（`.summarizing` ステート）は呼び出しをスキップすれば他に影響なし。**

### タイマー設計

```swift
// RecapViewModel+Timers.swift:4–23
timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    Task { @MainActor in self?.recordingDuration += 1 }
}
levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
    Task { @MainActor in self?.updateAudioLevels() }
}
```

**移植時の注意:** `Timer` クロージャ内の `Task { @MainActor in }` パターンは Swift 6 strict concurrency と相性が悪い場合がある。sokki では `AsyncStream` + `for await` ループへの置き換えを検討すること。

### OnboardingViewModel

`isMicrophoneEnabled`・`isAutoDetectMeetingsEnabled`（Screen + Notification の両方が必要）・`isLiveTranscriptionEnabled` を管理。`completeOnboarding()` が `userPreferencesRepository.updateOnboardingStatus(true)` を呼び出し、`OnboardingDelegate.onboardingDidComplete()` で MenuBarPanelManager に通知、パネル遷移アニメーションが走る。

**`isAutoSummarizeEnabled` および LLM 関連フォームは省略可。** sokki のオンボーディングはマイク権限と通知権限の 2 項目のみで十分。

### PreviousRecapsViewModel

`GroupedRecordings`（`todayRecordings` / `thisWeekRecordings` / `allRecordings`）を `@Published` で保持。3 秒おきの `Timer` ポーリングで処理中録音状態変化を反映する設計だが、**sokki では SwiftData の `@Query` マクロで宣言的に監視できるためタイマーポーリングは不要**。

### SummaryViewModel — **省略可**

`currentRecording: RecordingInfo?` を中心に `processingStage` / `isProcessing` / `hasSummary` の computed property を持つ。`copySummary()` は `NSPasteboard.general` 経由でテキストをコピー。**sokki は要約機能を採用しないため、この ViewModel と `SummaryPanel` / `MenuBarPanelManager+Summary.swift` は実装不要。** 他サブシステムへの影響なし。

### AppSelectionViewModel

システム上で音声を出力しているアプリを `AudioProcessController` から取得し、ミーティングアプリか否かでソートするドロップダウン VM。`state: AppSelectionState`（`.noSelection` / `.showingDropdown` / `.selected(app)` の 3 ケース列挙）。`selectApp(_:)` → `delegate?.didSelectApp(app.audioProcess)` → `RecapViewModel.didSelectApp(_:)` と伝播。RecapViewModel は `AppSelectionCoordinatorDelegate` と `AppSelectionDelegate` の 2 プロトコルを適合している点に注意。

---

## Keychain サービス

`final class KeychainService: KeychainServiceType`（非 actor）が `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete` を直接呼ぶ。

```swift
// KeychainServiceType.swift:9–14
protocol KeychainServiceType {
    func store(key: String, value: String) throws
    func retrieve(key: String) throws -> String?
    func delete(key: String) throws
    func exists(key: String) -> Bool
}
```

`store()` は `errSecDuplicateItem` で自動的に `SecItemUpdate` にフォールバックする upsert パターン。`retrieve()` は `errSecItemNotFound` で throw せず `nil` を返す。

現在のキーは `KeychainKey.openRouterApiKey`（LLM 用）のみ。**sokki での適用:** `KeychainKey` に `case translationApiKey = "translation_api_key"` を追加し `var key: String { "com.sokki.\(rawValue)" }` に変えるだけで転用できる。`KeychainService` 本体のロジックは変更不要。

**`KeychainAPIValidator` と `GeneralSettingsViewModel` の LLM プロバイダ選択 UI は省略可。** `KeychainService` の 4 メソッドは独立しており影響なし。

---

## 移植時の勘所

### DI 設計と SwiftData 置換

`DependencyContainer` で `ModelContainer` を 1 回だけ生成し、`ModelContext`（`mainContext`）を Repository 系クラスに注入する形が Recap の構造と整合する。SwiftData の `@Query` は View 内専用なので、Repository 層では `ModelContext.fetch(_:)` を使い async メソッドとして公開する。

### actor 境界と Sendable

- `RecapViewModel` / `DependencyContainer` / `PermissionsHelper` は全て `@MainActor`。
- `KeychainService` は非 actor の `final class`。Security API は同期かつスレッドセーフ。
- SwiftData の `ModelContext` は `@MainActor` に閉じて使う限り安全。バックグラウンド処理が必要なら `ModelActor` を経由する。
- **`@Model` クラスのインスタンスは actor 境界を越えて渡してはいけない。** ViewModel には `PersistentIdentifier` か軽量 DTO 構造体（例: `RecordingInfo`）を渡す設計にする（CLAUDE.md 記載の注意事項と一致）。
- `StatusBarManager` は Recap では非 `@MainActor` だが、Swift 6 strict concurrency を有効にすると警告が出る可能性がある。sokki では `@MainActor` を付け、`@objc` メソッド内を `Task { @MainActor in }` に書き換えることを推奨。

### sokki 用 entitlements チェックリスト

| entitlement | Phase 1 | Phase 2 以降 |
|---|---|---|
| `com.apple.security.app-sandbox` | 必須 | 必須 |
| `com.apple.security.device.audio-input` | 必須 | 必須 |
| `com.apple.security.network.client` | 翻訳 API 使用時 | 必須 |
| `com.apple.security.screen-capture` | 不要 | SCStream 採用時に追加 |
| `NSAudioCaptureUsageDescription` | 必須（Info.plist）| 必須 |
| `NSScreenCaptureUsageDescription` | 不要 | SCStream 採用時に追加 |

**Keychain とバンドル識別子の注意:** `kSecAttrService` はバンドル識別子でグルーピングされる。開発ビルド（`com.sokki.dev`）と本番ビルド（`com.sokki`）でキーが共有されないため、テスト時はキー名プレフィックスで区別する等の配慮が必要。

**SlidingPanel の SwiftPM 対応:** `NSPanel` サブクラスは `SokkiKit`（Library ターゲット）に置き、`sokki` 実行ファイルターゲットからインポートする構成が CLAUDE.md のアーキテクチャ指針と一致する。`NSPanel` / `NSStatusBar` は AppKit であり、macOS ターゲットでは追加フレームワークリンクなしに `import AppKit` で使用できる。
