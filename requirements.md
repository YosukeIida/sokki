# 要件定義書 — sokki（速記）

> 作成日: 2026-03-28
> 更新日: 2026-05-27
> ステータス: Draft v0.2
> 対象OS: macOS 15+ (Apple Silicon)

---

## 1. 概要

会議・講義・インタビュー・独り言など、多様な音声シーンに対応する macOS ネイティブの音声文字起こしアプリ。

**三本柱**: ローカル完結 / 日本語高精度 / 声紋を記憶する話者分離

既存ツール（MacWhisper Pro、WhisperMate、Granola）が達成できていない「日本語 diarization × 声紋永続記憶 × Homebrew 配布」の同時実現を目標とする。

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
- **FR-CAP-3** マイク＋システム音声を同時キャプチャできること
  - 実装: `ScreenCaptureKit`（単一 SCStream、`SCStreamOutputType` でレーン分岐）
  - macOS 15 以降で `captureMicrophone = true` が利用可能
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

- **FR-DIA-1** 話者分離（誰がいつ話したか）をオプションで実行できること
  - 実装: `SpeakerKit`（Pyannote v4 on Core ML、312–900× realtime）
- **FR-DIA-2** 話者ラベルを文字起こしセグメントに付与できること（`Speaker_00` 等）
- **FR-DIA-3** 声紋ベクトル（256 次元）を SwiftData に永続化し、次回セッションでも同じ話者を認識できること
  - コサイン類似度（vDSP）で照合、閾値 0.82（設定変更可）
  - 指数移動平均（alpha=0.1）でセッションごとにプロファイルを更新
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

## 4. 非機能要件

- **NFR-1** ローカル完結（音声データをクラウド送信しないこと）
- **NFR-2** Apple Silicon (M1 以降) で快適に動作すること
- **NFR-3** バックグラウンド推論は ANE (Apple Neural Engine) にオフロードすること
- **NFR-4** macOS 15 (Sequoia) 以降を対象とすること
- **NFR-5** GitHub + Homebrew Cask で配布できること（コード署名なしでも動作可能な形）
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
```

| エンジン | 優先度 | 状態 | 備考 |
|----------|--------|------|------|
| WhisperKit (large-v3-turbo) | Primary | ✅ 利用可 | 日本語精度最優先、CER 約4-8% |
| Apple SpeechAnalyzer | Secondary | macOS 26+ | 速度最優先（34分→45秒）、追加 DL 不要 |

### コンポーネント一覧

| レイヤー | 技術 | 役割 |
|----------|------|------|
| 音声キャプチャ | ScreenCaptureKit（単一 SCStream） | マイク + システム音声同時取得、レーン分離 |
| 文字起こし | WhisperKit v1.0 (`argmax-oss-swift`) | Core ML / ANE 最適化、日本語対応 |
| 話者分離 | SpeakerKit (Pyannote v4 Core ML) | 312–900× realtime |
| 声紋永続化 | SwiftData + vDSP コサイン類似度 | セッション間話者認識の核心 |
| データ永続化 | SwiftData (SQLite) | セッション管理 |
| UI | SwiftUI | macOS ネイティブ |
| 後処理 (optional) | OpenAI 互換エンドポイント | Ollama / LM Studio / Claude API など外部管理 |

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
| Phase 1 (MVP) | マイク録音 + WhisperKit バッチ文字起こし + 最小 SwiftUI | 🔄 ほぼ完了（Issue #3-#5 残り） |
| Phase 2 | システム音声 + リアルタイムストリーミング + 波形 UI + 音声同期再生 | ⬜ 未着手 |
| Phase 3 | SpeakerKit 話者分離 + 声紋永続化 + SpeakerProfileView | ⬜ 未着手 |
| Phase 4 | Apple SpeechAnalyzer エンジン + SRT/VTT エクスポート + ファイルインポート | ⬜ 未着手 |
| Phase 5 | LLM 連携（話者名推定・サマリー）+ Homebrew Cask 配布 | ⬜ 未着手 |

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
- `#7` SCStream でシステム音声キャプチャ
- `#8` Both モード（マイク+システム同時）
- `#9` リアルタイムストリーミング文字起こし
- `#10` 波形表示 UI
- `#11` セグメントクリックで音声再生

### Phase 3
- `#12` SpeakerKit 話者分離
- `#13` 声紋照合（EmbeddingMatcher）
- `#14` 話者プロファイル永続化（EMA）
- `#15` 話者カラーバー付き SessionDetailView
- `#16` SpeakerProfileView UI

### Phase 4〜5
- `#17` SRT/VTT エクスポート確認
- `#18` Apple SpeechAnalyzer エンジン
- `#19` ファイルインポート
- `#20` LLM 話者名推定
- `#21` Homebrew Cask 配布

---

## 9. 未決定事項 (Open Questions)

- [x] ~~アプリ名~~ → **sokki**（速記）
- [x] ~~ビルドシステム~~ → xcodegen + SPM（xcodeproj 生成済み）
- [ ] claude.ai/design でのデザインシステム設定
- [ ] Homebrew Cask リポジトリの管理方法（個人 tap vs 公式）
- [ ] コード署名なし配布時の Gatekeeper 回避方法のドキュメント化
- [ ] SpeakerKit の日本語音声での DER（話者誤認識率）の実測評価
- [ ] リアルタイム文字起こし時のバッファリング戦略（チャンクサイズ）
- [ ] 声紋照合閾値の日本語音声での最適値（暫定 0.82、実測後調整）

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
