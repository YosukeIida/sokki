# 要件定義書 — macOS 音声文字起こしアプリ

> 作成日: 2026-03-28  
> ステータス: Draft v0.1  
> 対象OS: macOS 15+ (Apple Silicon)

---

## 1. 概要

会議・講義・インタビュー・独り言など、多様な音声シーンに対応するmacOSネイティブの音声文字起こしアプリ。ローカル完結・日本語対応・話者分離を三本柱とし、WhisperMateでは実現できない「日本語diarization + 柔軟なエクスポート + Homebrew配布」を目標とする。

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

- **FR-CAP-1** マイク入力（AirPods Pro含む）をキャプチャできること
- **FR-CAP-2** システム音声（Zoom / Meet / Teams などの相手の声）をキャプチャできること
- **FR-CAP-3** マイク＋システム音声を同時ミックスしてキャプチャできること
  - 実装: `ScreenCaptureKit` (SCStreamConfiguration)
- **FR-CAP-4** 既存の動画・音声ファイル（.mp4, .m4a, .wav, .mp3）を読み込めること

### 3.2 文字起こしエンジン

- **FR-ASR-1** リアルタイム文字起こし（録音しながら字幕表示）に対応すること
- **FR-ASR-2** バッチ文字起こし（録音ファイルを後処理）に対応すること
- **FR-ASR-3** 日本語に対応すること（精度優先）
- **FR-ASR-4** 文字起こしエンジンを切り替えられること（後述 §5 参照）
- **FR-ASR-5** エンジンは `TranscriptionEngine` プロトコルで抽象化し、追加・交換を容易にすること

### 3.3 話者分離

- **FR-DIA-1** 話者分離（誰がいつ話したか）をオプションで実行できること
  - 実装: `SpeakerKit` (WhisperKit付属 / Pyannote v4 on Core ML)
- **FR-DIA-2** 話者ラベルを文字起こしセグメントに付与できること (`Speaker_00`, `Speaker_01`, …)
- **FR-DIA-3** LLMを用いた話者名の自動推定をオプションで実行できること
  - 実装: OpenAI互換エンドポイントへのHTTP呼び出し（Ollama / LM Studio / Claude API など）
  - アプリはモデル管理に関知しない。ユーザーが設定する `baseURL` + `model` を使うだけ

### 3.4 データ管理

- **FR-DATA-1** セッション単位でデータを管理できること
- **FR-DATA-2** 各セッションは以下のデータを保持すること

```
Session
├── id: UUID
├── title: String          // 例: "Meeting_20260328"
├── created_at: Date
├── audio_file_path: URL   // ローカル音声ファイルへの参照
└── segments: [Segment]
      ├── id: UUID
      ├── start: TimeInterval   // 秒
      ├── end: TimeInterval
      ├── text: String
      └── speaker: String?      // "Speaker_00" など (optional)
```

- **FR-DATA-3** セグメントをクリックするとその時刻の音声を再生できること（音声ファイルとの同期）

### 3.5 エクスポート

| 形式 | 用途 | 備考 |
|------|------|------|
| Markdown | Obsidian連携 / 全文コピー | 話者名・タイムスタンプ付き |
| SRT | 動画字幕ファイル | 標準字幕フォーマット |
| VTT | Web動画字幕 | HTML5 video対応 |
| プレーンテキスト | 最小出力 | 話者・時刻なし |

- **FR-EXP-1** Markdownエクスポートは以下のフォーマットで出力すること

```markdown
## Meeting_20260328

**Speaker_00** `00:00:00`
こんにちは、はじめまして。

**Speaker_01** `00:00:07`
後の成功の基盤となります...
```

---

## 4. 非機能要件

- **NFR-1** ローカル完結（音声データをクラウド送信しないこと）
- **NFR-2** Apple Silicon (M1以降) で快適に動作すること
- **NFR-3** バックグラウンド推論はANE (Apple Neural Engine) にオフロードすること
- **NFR-4** macOS 15 (Sequoia) 以降を対象とすること
- **NFR-5** GitHub + Homebrew Cask で配布できること（コード署名なしでも動作可能な形）
- **NFR-6** Xcode + Swift Package Manager で管理できること

---

## 5. 技術スタック

### エンジン構成

```
protocol TranscriptionEngine {
    func transcribe(_ audio: AVAudioPCMBuffer) async throws -> [TranscriptionSegment]
}
```

| エンジン | 優先度 | 状態 | 備考 |
|----------|--------|------|------|
| WhisperKit (large-v3-turbo) | Primary | ✅ 今すぐ利用可 | 日本語精度最優先 |
| Apple SpeechAnalyzer | Secondary | ✅ macOS 26で利用可 | 速度最優先・追加DL不要 |

### コンポーネント一覧

| レイヤー | 技術 | 役割 |
|----------|------|------|
| 音声キャプチャ | ScreenCaptureKit | マイク + システム音声同時取得 |
| 文字起こし | WhisperKit | Core ML最適化 / 日本語対応 |
| 話者分離 | SpeakerKit (Pyannote v4) | Core ML / ANE動作 |
| データ永続化 | SwiftData (SQLite) | セッション管理 |
| UI | SwiftUI | macOSネイティブ |
| 後処理 (optional) | OpenAI互換エンドポイント | Ollama / LM Studio / Claude API など外部管理 |

---

## 6. 配布・開発環境

- **配布方法**: GitHub + Homebrew Cask
  ```
  brew install --cask <app-name>
  ```
- **ターゲットユーザー**: 開発者本人 + 機械学習理論研究室メンバー
- **リポジトリ**: GitHub (TMLlaboratory または個人アカウント)
- **開発環境**: Xcode + Swift Package Manager + uv (Python補助スクリプト用)

---

## 7. 開発フェーズ（暫定）

| フェーズ | 内容 | 優先度 |
|----------|------|--------|
| Phase 1 (MVP) | ScreenCaptureKit音声取得 + WhisperKit文字起こし + SwiftUI最小UI | 高 |
| Phase 2 | セッション管理 (SwiftData) + 音声同期再生 + Markdownエクスポート | 高 |
| Phase 3 | 話者分離 (SpeakerKit) + 話者ラベルUI | 中 |
| Phase 4 | Apple SpeechAnalyzerエンジン追加 + SRT/VTTエクスポート | 中 |
| Phase 5 | OpenAI互換エンドポイント連携（話者名推定 / サマリー）+ Homebrew配布 | 低 |

---

## 8. 未決定事項 (Open Questions)

- [ ] アプリ名
- [ ] Homebrew Caskリポジトリの管理方法（個人tap vs 公式）
- [ ] コード署名なし配布時のGatekeeper回避方法のドキュメント化
- [ ] SpeakerKitの日本語音声でのDER（話者誤認識率）の実測評価
- [ ] リアルタイム文字起こし時のバッファリング戦略（チャンクサイズ）

---

## 9. 設計方針：管理責任をアプリに持ち込まない

変化の激しいコンポーネントはアプリの外で管理し、アプリ本体は**音声 → テキスト → 表示/保存**というコアに集中する。

| コンポーネント | 管理者 | アプリの対応 |
|---|---|---|
| ScreenCaptureKit | Apple | 直接利用（ラッパー不要） |
| WhisperKit / SpeakerKit | Argmax (OSS) | SPMで追従 |
| SwiftData | Apple | 直接利用 |
| LLM | **ユーザー自身** | OpenAI互換HTTP呼び出しのみ |

LLM連携はエンドポイントURL・APIキー・モデル名をユーザーが設定するだけで、アプリはモデルの追加・バージョンアップに無関係。

```swift
struct LLMSettings {
    var baseURL: URL     // 例: http://localhost:11434
    var apiKey: String?  // Ollamaなら不要
    var model: String    // 例: "llama3.2"
}
```

---

*このドキュメントはプロジェクトの進行に合わせて随時更新する。*
