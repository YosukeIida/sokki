<!-- sokki 調査ドキュメント / 生成: 2026-06-26 / Recap 以外の参考 OSS -->
# sokki OSS リファレンス調査 — ローカル音声文字起こし実装の全景

調査日: 2026-06-26 / macOS 14.2–26 / Apple Silicon

---

## 調査結果サマリー（16プロジェクト）

| プロジェクト | ライセンス | macOS 最低 | キャプチャ手法 | sokki 優先度 |
|---|---|---|---|---|
| **AudioCap** (insidegui) | 不明 | 14.4 | Core Audio Tap | Phase 2 設計参考 |
| **Apple WWDC24 サンプル** | Apple Sample | 14.2 | Core Audio Tap | 一次リファレンス（流用可） |
| **AudioTee** (makeusabrew) | MIT | 14.2 | Core Audio Tap | stdout streaming 設計参考 |
| **Recap** (RecapAI) | MIT | 15.0 | Core Audio Tap + AVAudioEngine | **最重要**・sokki と同構成 |
| **Parrot** (turantekin) | MIT | 14.0 | ScreenCaptureKit + AVAudioEngine | Phase 2 SCK 設計参考 |
| **Scripta 記事** (thehwang) | MIT | 15.0 | ScreenCaptureKit | **Voice Processing IO の罠** |
| **argmax-oss-swift / WhisperAX** | MIT | 14.0 | — (ASRライブラリ) | **直接依存。今すぐ参照** |
| **FluidAudio** (FluidInference) | Apache 2.0 | 14.0 | — (ASRライブラリ) | SpeakerKit 代替・話者分離強化 |
| **OpenSuperWhisper** (Starmel) | MIT | 14.0 | AVAudioEngine | ホットキー dictation 参考 |
| **whisper-server** (pfrankov) | MIT | 14.6 | — | OpenAI 互換ローカル API 設計 |
| **anarlog** (fastrepl/Hyprnote) | MIT | — | Core Audio Tap (Rust cidre) | ringbuf async 設計参考 |
| **ambient-voice** (Marvinngg) | MIT | 26 | ScreenCaptureKit | OCR コンテキスト注入 / FloatingPanel |
| **swift-scribe** (FluidInference) | MIT | 26 | — | macOS 26 SpeechTranscriber 先行例 |

---

## 各プロジェクトの詳細

### 1. AudioCap — Core Audio Tap の原典 [confidence: high]

[github.com/insidegui/AudioCap](https://github.com/insidegui/AudioCap)

macOS 14.4 で追加された `AudioHardwareCreateProcessTap` 系 API の事実上の一次リファレンス。後続 OSS（Recap・Scripta 等）はすべてこの実装を起点に設計している。

**ProcessTap の手順（10ステップ）:**
1. PID → `AudioObjectID` 変換（`kAudioHardwarePropertyTranslatePIDToProcessObject`）
2. `CATapDescription` 作成
3. `AudioHardwareCreateProcessTap()`
4. Aggregate Device 辞書を構成（UID・drift compensation・mute 設定）
5. `AudioHardwareCreateAggregateDevice()`
6. フォーマット取得
7. `AudioDeviceCreateIOProcIDWithBlock()` でコールバック登録
8. `AudioDeviceStart()`
9. バッファを AVAudioFile へ書き込み
10. 停止・クリーンアップ

**注意:** ライセンスが README に明記なし。コード流用は避け、WWDC24 公式サンプルを一次ソースとして使うこと。

**sokki 活用:** Phase 2 で「特定アプリのみをタップ」する場合（SCStream より細粒度）、`ProcessTapRecorder` クラスの設計ベースとして参照。

---

### 2. Apple 公式サンプル — Capturing system audio with Core Audio taps [confidence: high]

[developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)

macOS 14.2 で API 導入、14.4 でパーミッションモデルが整備。WWDC24 サンプルコードリポジトリにもミラーあり（artemnovichkov/wwdc24-samplecode）。

Apple のサンプルコードライセンスは改変・配布可（App Store 配布も可）。**AudioCap より法的に安全**。

**重要な実装知見:**
- I/O Proc はオーディオスレッドで呼ばれるため処理を最小化し、別キューへオフロード必須
- デバイス変更時はリソースを完全に再生成すること（途中変更は音声グリッチの原因）
- サンプルレート 22.05kHz 固定化推奨（文字起こし用途）

---

### 3. AudioTee — stdout PCM ストリーミング CLI [confidence: high]

[github.com/makeusabrew/audiotee](https://github.com/makeusabrew/audiotee) — MIT / macOS 14.2+

200ms ごとに raw PCM を stdout へ、ログは stderr に分離して出力する純粋なパイプ部品。`| whisper.cpp` 等への直接パイプが可能。AudioCap がアプリとして完結するのに対し、単体バイナリとして設計されている。

Hyprnote 初期版はこれをサブプロセスとして起動し stdout を Rust の ringbuf に流す設計を採用していた。

**sokki 活用:** sokki は Swift ネイティブなので直接利用する理由は薄いが、「Core Audio Tap を最小限のコードで実装する参照実装」として MIT のソースコードを読む価値あり。

---

### 4. Recap — sokki と最も近い先行実装 [confidence: high]

[github.com/RecapAI/Recap](https://github.com/RecapAI/Recap) — MIT / macOS 15.0+ / Apple Silicon 専用

**最重要参照対象。** 技術スタックが sokki と最も一致している。

- **音声キャプチャ:** Core Audio Tap（システム音声）+ AVAudioEngine（マイク）
- **ASR:** WhisperKit (MLX ベース) + ローカルモデルダウンロード UI
- **LLM:** Ollama（デフォルト・ローカル）または OpenRouter（クラウドフォールバック）
- **UI:** SwiftUI 全画面。設定 / 録音 / 履歴一覧の3ビュー構成

**sokki 活用:** MIT ライセンスなのでコードの参照・流用が可能。特に「Core Audio Tap + AVAudioEngine の同時使用」と「WhisperKit モデル選択 UI」の実装をそのまま参考にできる。録音後バッチ処理の設計は Issue #3（durationSeconds 更新）の実装にも参考になる。

---

### 5. Parrot — SCK + WhisperKit + SwiftData の完成例 [confidence: high]

[github.com/turantekin/Parrot](https://github.com/turantekin/Parrot) — MIT / macOS 14.0+

Recap との最大の違いは ScreenCaptureKit を使用している点。SCK 設定の参照として：

```swift
let config = SCStreamConfiguration()
config.capturesAudio = true
config.excludesCurrentProcessAudio = true  // フィードバックループ防止
config.sampleRate = 16_000                 // Whisper 最適
config.channelCount = 1
config.width = 2    // 動画ペイロードを最小化
config.height = 2
```

**注意:** SCK は「画面収録」権限を要求するため、音声だけ取りたいユーザーには心理的ハードルが高い。Core Audio Tap（音声専用パーミッション）を採用した Recap の方針が sokki のユーザー体験的には優れている可能性がある。

---

### 6. Scripta 実装記事 — ハマりどころの宝庫 [confidence: high]

[dev.to/thehwang — Building a 100% Local Meeting Transcription App for macOS](https://dev.to/thehwang/building-a-100-local-meeting-transcription-app-for-macos-with-whispercpp-and-screencapturekit-33m7)

**今すぐ読むべき記事。** 実装時に踏んだ落とし穴の詳細記録。

**Voice Processing IO の罠:** Voice Processing を有効にすると AVAudioEngine のマイク出力が **9チャンネル形式**になり `AVAudioConverter` が無言でクラッシュする。workaround: チャンネル 0 を手動抽出し、線形補間リサンプリングをオーディオスレッドで直接実施。あわせて ducking も無効化必須：

```swift
config.enableAdvancedDucking = false
config.duckingLevel = .min
```

**sokki 活用:** sokki が AVAudioEngine（Phase 1）→ SCStream（Phase 2）の移行を予定している点で、この罠はそのまま当たる。今の Phase 1 実装に上記設定を仕込んでおくと移行コストが下がる。

---

### 7. argmax-oss-swift / WhisperAX — sokki の直接依存ライブラリ [confidence: high]

[github.com/argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) — MIT / macOS 14.0+

v1.0.0（2026-05）に WhisperKit + SpeakerKit + TTSKit が統合。ICML 2025 で発表。

**ストリーミング性能（ICML 2025）:**
- Hypothesis テキスト: **0.45 秒**平均レイテンシ
- 確定テキスト: ~1.7 秒
- WER: **2%**（Deepgram と同等。OpenAI gpt-4o-transcribe を上回る）
- Text Decoder が 45% レイテンシ削減（8.4ms → 4.6ms）
- 消費電力 75% 削減（1.5W → 0.3W）

**LocalAgreement ポリシー:** Hypothesis（仮確定・灰色表示）と Confirmed（確定・白色表示）の二系統を出力。リアルタイム字幕の体験に直結。

**sokki 活用:** `Examples/WhisperAX/WhisperAX.xcodeproj` をそのまま開いて SpeakerKit 統合の SwiftUI パターンを確認すること。Hypothesis/Confirmed 二系統の UI 表示は sokki の Phase 2 リアルタイム字幕で直接採用できる。

---

### 8. FluidAudio — WhisperKit に次ぐ話者分離の選択肢 [confidence: high]

[github.com/FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio) — Apache 2.0 / macOS 14.0+

**M4 Pro で 190x リアルタイム**（1時間音声を約19秒で処理）。ANE に特化。

**ASR モデル:**
- Parakeet TDT v3（0.6b）: 多言語25言語 + 日本語
- Parakeet EOU（120m）: ストリーミング ASR + 発話終了検出

**話者分離:**
- **LS-EEND**: 最大 10 話者, 100ms 更新、ストリーミング向き
- **Sortformer**: 最大 4 話者、話者 ID の安定性が高い
- **Pyannote 3.1**: 最も柔軟だが低速

```swift
// SPM で追加
.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")

// 使用例
let diarizer = try await LSEENDDiarizer(variant: .dihard3)
let timeline = try diarizer.processComplete(samples, sourceSampleRate: 16_000)
```

**sokki 活用:** SpeakerKit で話者分離が不十分な場合（4人以上の会議等）のフォールバック候補。Apache 2.0 なので商用・再配布ともに問題なし。

---

### 9. OpenSuperWhisper — ホットキー dictation の参照実装 [confidence: high]

[github.com/Starmel/OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) — MIT / macOS 14.0+

Swift 93.6%。whisper.cpp + Parakeet (FluidAudio)。グローバルホットキー（キーコンビネーション or 単修飾キー、ホールド録音対応）。マルチチャンネル録音の自動 mono ダウンミックス実装あり。

**sokki 活用:** Phase 3 以降で「ホットキー音声入力」機能を追加する際、`NSEvent.addGlobalMonitorForEvents` によるグローバルホットキー登録のパターンを参照。

---

### 10. whisper-server — OpenAI 互換ローカル API サーバー [confidence: high]

[github.com/pfrankov/whisper-server](https://github.com/pfrankov/whisper-server) — MIT / macOS 14.6+

Swift 81.5%。`POST /v1/audio/transcriptions` エンドポイントを `localhost:12017` で提供。SSE（Server-Sent Events）による **リアルタイムストリーミング**対応。VAD チャンキングで repeated text アーティファクトを防止。

**sokki 活用:** sokki をローカル STT サーバーとして他ツールから呼び出せるようにする際の設計参考。Phase 3+ の開発者向け機能として検討。

---

### 11. Hyprnote / anarlog — Rust ring buffer による Core Audio Tap 設計 [confidence: high]

[github.com/fastrepl/anarlog](https://github.com/fastrepl/anarlog)（旧 Hyprnote, YC S25）— MIT

音声キャプチャ層が純 Rust で実装されており、macOS では `cidre` Rust バインディング経由で Core Audio Tap API を直接呼び出す。lock-free ringbuf（65,536 サンプル）で async Rust stream に変換している。

**ringbuf 設計:**
```
Core Audio Tap コールバック → ringbuf (65,536 samples) → RingbufAsyncReader → async Rust Stream → STT
```

**sokki 活用:** Rust 実装そのものは使えないが、「I/O コールバックを async に変換する」設計思想を Swift の `AsyncStream` + actor 境界設計に転用できる。

---

### 12. ambient-voice — OCR コンテキスト注入 + FloatingPanel [confidence: medium]

[github.com/Marvinngg/ambient-voice](https://github.com/Marvinngg/ambient-voice) — MIT / **macOS 26 専用**

SpeechAnalyzer に Vision OCR で取得したキーワードを `contextualStrings` として注入することで専門用語の認識精度を向上させる独自アーキテクチャ。

**sokki 活用:** macOS 26 普及後の Phase 4+ で、専門用語の多い会議での差別化機能として OCR コンテキスト注入を検討。FloatingPanel の実装も参照可。

---

### 13. swift-scribe — macOS 26 SpeechTranscriber の先行例 [confidence: high]

[github.com/FluidInference/swift-scribe](https://github.com/FluidInference/swift-scribe) — MIT / **macOS 26 専用**

Apple の SpeechTranscriber + Foundation Models Framework + FluidAudio を組み合わせたモジュラー設計。Audio / Transcription / AI / Views / Models / Storage の6レイヤー分離は sokki の将来的なアーキテクチャ参考になる。

---

### 14. NSPanel FloatingPanel パターン — リアルタイム字幕 UI の基盤 [confidence: high]

[cindori.com/developer/floating-panel](https://cindori.com/developer/floating-panel)

```swift
class FloatingPanel<Content: View>: NSPanel {
    init(...) {
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        // canJoinAllSpaces: Zoom/Teams のフルスクリーン Space にも表示
        sharingType = .none  // 画面収録に映り込まない
    }
}
```

**sokki 活用:** Phase 2 の「リアルタイム字幕オーバーレイ」の実装基盤。SokkiKit に `.floatingPanel(isPresented:)` ViewModifier として実装。

---

### 15. Apple Translation Framework — リアルタイム翻訳の最短経路 [confidence: high]

[developer.apple.com/documentation/translation/](https://developer.apple.com/documentation/translation/) — macOS 14.4+

**sokki の「リアルタイム翻訳」を取り込む際の第一候補。**

- 完全オンデバイス（翻訳コンテンツは Apple に送信されない）
- API コストゼロ
- sokki の最低要件（macOS 15+）を満たす
- 言語モデルは初回ダウンロード（ユーザー許可プロンプトあり）

```swift
// WhisperKit の Confirmed テキストが出るたびに翻訳するパターン
let session = TranslationSession(source: .japanese, target: .english)
for await segment in whisperKit.confirmedTextStream {
    let translated = try await session.translate(segment.text)
    await MainActor.run {
        overlayView.appendSegment(translated, speaker: segment.speaker)
    }
}
```

Phase 2 のリアルタイム字幕と同時実装が推奨。外部 API（DeepL / OpenAI）より UX・コスト・プライバシーの3点で優れる。

---

## sokki 採用判断まとめ

### 今すぐ参照すべき（Phase 1 完了前）

1. **Scripta 実装記事** — Voice Processing IO の罠を今の Phase 1 実装に仕込まれていないか確認
2. **WhisperAX サンプル** (`Examples/WhisperAX/`) — Hypothesis/Confirmed 二系統 UI を Issue #2 の前に把握

### Phase 2（SCStream 移行・リアルタイム字幕）で採用

| 用途 | 採用 | 参照先 |
|---|---|---|
| システム音声キャプチャ | Core Audio Tap | Recap + WWDC24 サンプル |
| マイクキャプチャ | AVAudioEngine | Recap |
| 字幕オーバーレイ | NSPanel FloatingPanel | cindori パターン |
| リアルタイム翻訳 | Apple Translation Framework | Apple ドキュメント |

### Phase 3 以降のオプション

| 機能 | 選択肢 | ライセンス |
|---|---|---|
| 話者分離強化 | FluidAudio LS-EEND | Apache 2.0 |
| ホットキー dictation | OpenSuperWhisper 参照 | MIT |
| ローカル API サーバー | whisper-server 参照 | MIT |
| macOS 26 移行 | swift-scribe / ambient-voice 参照 | MIT |

**ライセンス注意:** AudioCap のみライセンス不明。設計参考に留め WWDC24 公式サンプルを一次ソースとして使うこと。whisper-mac はライセンス不明のためコード流用不可。
