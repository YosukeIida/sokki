# 競合調査レポート — sokki の独自性分析

> 作成日: 2026-03-28
> 目的: 既存の音声文字起こしツールとの比較・差別化ポイントの確立

---

## 調査方法

OSS・フリー・有料を問わず、macOSネイティブアプリ・クロスプラットフォームアプリ・Webサービス・CLI ツールを広く調査した。

---

## 1. macOS ネイティブアプリ

| アプリ | ローカル完結 | 日本語精度 | 話者分離 | LLM（Ollama/Claude/OpenAI）| SwiftUI | Homebrew Cask |
|--------|------------|-----------|---------|--------------------------|---------|--------------|
| **MacWhisper Pro** | ✅ | 良好 | △ Beta (1エンジン限定) | △ Claudeカスタムプロンプト不安定 | ✅ | ✅ |
| **WhisperMate** | △ (Deepgramはクラウド) | 良好 | △ (高精度はクラウド) | Ollamaのみ | ✅ | ❌ |
| **Aiko** | ✅ | 良好 | ❌ 未対応 | ❌ | ✅ | ❌ |
| **SpeechPulse** | ✅ | 良好 | ✅ | △ (ClaudeなしOpenAI+Ollama) | ❌ Windows主体 | ❌ |
| **Whisper Snapper** | △ (diarizationはクラウド) | △ | △ (Deepgramかクラウド) | ❌ | ✅ | ❌ |
| **Superwhisper** | ✅ | 良好 | ❌ (dictation専用) | ❌ | ✅ | ❌ |
| **Whisper Notes** | ✅ | 良好 | ❌ | ❌ | ✅ | ❌ |

### 主要競合の詳細

#### MacWhisper Pro（最も近い競合）
- 2025年3月にdiarization追加。ただし Beta 扱い、WhisperKit エンジン専用
- Claude API は連携対応しているが **カスタムプロンプトが不安定**（OpenAI と同等に動かない）
- 日本語最適化モデルの選択肢なし（標準 Whisper large-v3 のみ）
- Pro ライセンス（$59–$80）がないと diarization 機能にアクセス不可
- クローズドソース

#### WhisperMate
- diarization の高精度動作に **Deepgram（クラウド）が必要**
- Homebrew Cask なし

---

## 2. クロスプラットフォーム / OSS

| ツール | ローカル完結 | 日本語 | 話者分離 | LLM柔軟性 | macOS native UI | Homebrew |
|--------|------------|--------|---------|-----------|----------------|---------|
| **Vibe** | ✅ | ✅ | ✅ | Ollama + Claude API | ❌ Tauri/クロス | ❌ |
| **pasrom/meeting-transcriber** | ✅ | ✅ | ✅ | Claude CLI + OpenAI互換 | ✅ SwiftUI | ✅ |
| **muesli** | ✅ | おそらく良好 | ✅ | OpenAI/OpenRouterのみ | ✅ SwiftUI | ❌ |
| **Buzz** | ✅ | ✅ | △ 開発中 | ❌ | ❌ Qt | ❌ |
| **Scriberr** | ✅ | ✅ | ✅ (WhisperX) | Ollama + OpenAI互換 | ❌ Docker/Web | ❌ |
| **whisperX (CLI)** | ✅ | ✅ | ✅ | ❌ | ❌ CLI | ❌ |
| **Meetily** | ✅ | ✅ | △ | Ollama（OpenAI計画中）| ❌ Rust/Tauri | ✅ |

### 注目 OSS の詳細

#### pasrom/meeting-transcriber（構成が最も近い）
- SwiftUI + WhisperKit + FluidAudio(pyannote CoreML) + Homebrew Cask という構成は sokki と非常に似ている
- ただし設計が「Zoom/Teams/Webex 自動検出のミーティングbot」に特化
- SRT エクスポートなし
- LLM は「Claude Code CLI」（開発者ツール）または OpenAI互換。3バックエンドを設定 UI で等価に扱う仕組みなし

#### Vibe
- diarization + Ollama + Claude API を兼ね備えるが **Tauri製（非SwiftUI）**
- macOS のネイティブ操作感なし

---

## 3. 日本語特化ツール

| ツール | ローカル | 日本語精度 | 話者分離 | macOS |
|--------|---------|-----------|---------|------|
| **Notta** | ❌ クラウド | ★★★★★（クラウド最高峰） | ✅ | Web/App |
| **AI GIJIROKU** | ❌ クラウド | ★★★★★（99.8%主張） | ✅ | Web/Zoom |
| **AmiVoice ScribeAssist** | ✅ オフライン | ★★★★★（日本語専用） | ✅ | ❌ **Windows専用** |
| **AutoMemo** | ❌ 専用ハード | ★★★★ | ✅ | ❌ |
| **okamyuji CLI** | ✅ | ★★★★ (Kotoba Whisper) | ❌ | CLI only |

**重要な発見：** 日本語diarization の最高品質ツール（AmiVoice）は **Windows 専用**。macOS でローカル完結しながら日本語diarization を実現するプロダクトは存在しない。

---

## 4. ギャップ分析：どこにも存在しない組み合わせ

### 6条件の同時充足

| 条件 | 充足するツール数（調査対象 ~20） |
|------|-------------------------------|
| ① ローカル完結 | 約12 |
| ② 高精度日本語 | 約8 |
| ③ 話者分離 | 約8 |
| ④ LLM バックエンド柔軟交換（Ollama/Claude/OpenAI を設定UIで等価切替） | **1以下** |
| ⑤ macOS SwiftUI ネイティブ UI | 約6 |
| ⑥ Homebrew Cask 配布 | 約3 |
| **全6条件を同時に満たすもの** | **0** |

### 具体的に「穴」がある領域

1. **日本語 diarization のローカル実行**
   pyannote は英語・欧州言語で学習されており、日本語音声での DER（話者誤認識率）を正面から扱うツールが存在しない。

2. **SRT エクスポート with 話者ラベル（ローカル完結）**
   話者付き SRT を生成できるローカルアプリが皆無。字幕制作・動画教材向けに空白地帯。

3. **Ollama を「クラウドAPIと同格」として扱う設定 UI**
   Ollama 対応ツールは多いが「おまけ機能」扱い。Ollama / Claude API / OpenAI API を同等に切り替えられる設定 UI を持つ完成したデスクトップアプリは確認できなかった。

4. **研究室・チーム向けローカルファースト配布**
   Homebrew Cask + ローカル完結 + 日本語 という組み合わせで「研究室メンバーが brew install 一発で使えるツール」は存在しない。

---

## 5. sokki の差別化ポジション

```
                    ローカル完結
                        ↑
        AmiVoice        |         pasrom/meeting-transcriber
        (Win専用)       |         MacWhisper Pro
                        |
日本語特化 ←────────────┼──────────────── 多言語汎用
                        |
       Notta             |         Vibe
       AI GIJIROKU       |         (Tauri)
                        ↓
                    クラウド依存
```

**sokki のターゲット象限：「ローカル完結 × 日本語重視 × macOS ネイティブ × 研究・開発者向け」**

この象限に完成したプロダクトは現時点で存在しない。

---

## 6. 調査対象ツール一覧（参考リンク）

- [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper)
- [WhisperMate](https://whispermate.app/en/)
- [Aiko — Sindre Sorhus](https://sindresorhus.com/aiko)
- [SpeechPulse](https://speechpulse.com/)
- [Vibe](https://github.com/thewh1teagle/vibe)
- [Buzz](https://github.com/chidiwilliams/buzz)
- [Scriberr](https://github.com/rishikanthc/Scriberr)
- [pasrom/meeting-transcriber](https://github.com/pasrom/meeting-transcriber)
- [muesli](https://github.com/pHequals7/muesli)
- [Meetily](https://github.com/Zackriya-Solutions/meetily)
- [whisperX](https://github.com/m-bain/whisperX)
- [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- [Notta](https://www.notta.ai/en/)
- [AmiVoice ScribeAssist](https://www.advanced-media.co.jp/en/)
- [AI GIJIROKU](https://gijiroku.ai/en/)
- [Kotoba Whisper](https://github.com/kotoba-tech/kotoba-whisper)
- [okamyuji/meeting-transcriber](https://github.com/okamyuji/meeting-transcriber)

---

*このドキュメントはプロジェクトの進行に合わせて随時更新する。*
