<!-- sokki 調査ドキュメント / 生成: 2026-06-26 / リアルタイム翻訳の技術選定 -->
# sokki — リアルタイム同時通訳機能 技術選定レポート

## SuperIntern の翻訳機能の実態

SuperIntern は「50言語超・双方向・ボットレス」を謳う macOS デスクトップアプリで、システム音声をローカルキャプチャして翻訳字幕を重畳表示する。[confidence: high — super-intern.com]

**「Google 翻訳 API を使っているはず」という仮説の検証：**
公式サイト・技術ドキュメントに使用 MT エンジンの記述はなく、確認不可。しかしアーキテクチャ的に最も自然な選択肢は Google Cloud Translation API v3 (NMT) であり、50言語超・REST 呼び出し・低コストという条件を最も安易に満たすのは同 API である。**【推定】** 確率 60–70% で Google Cloud Translation API v3 を後段 MT として利用していると推測する。[confidence: low — 公開情報なし]

---

## 1. Google Cloud Translation API v3 (Advanced)

### 概要

Cloud Translation の現行安定版。REST と gRPC 両方をサポート。135以上の言語ペアに対応し NMT ベース。カスタム用語集 (Glossary)・バッチ翻訳・ドキュメント翻訳に対応。[confidence: high — cloud.google.com/translate/pricing]

### 料金 (2026年6月)

| モデル | 無料枠 | 従量課金 |
|---|---|---|
| NMT (標準) | 500,000 文字/月 | **$20 / 100万文字** |
| LLM-based | なし | $10 IN + $10 OUT / 100万文字 |
| Adaptive LLM | なし | $25 IN + $25 OUT / 100万文字 |

[confidence: high — cloud.google.com/translate/pricing]

### ストリーミング可否

**Cloud Translation API v3 にテキストのストリーミング翻訳エンドポイントは存在しない。** `translateText` は同期 REST/gRPC リクエスト。リアルタイム翻訳には「WhisperKit が partial transcript を確定するたびに HTTP リクエストを投げる」設計になる。レイテンシは往復 50–150ms 程度 (東京リージョン)。[confidence: high]

### Swift からの呼び出し

公式 Swift SDK は存在しない。REST エンドポイントを `URLSession` で直接叩くのが実装コスト最小。

---

## 2. Google Cloud Media Translation API

**廃止済み — 採用不可。**

Media Translation API は **2024年7月1日をもってサービス終了**。Google は代替として「Cloud Speech-to-Text + Cloud Translation API の組み合わせ」を推奨している。Python/Go クライアントライブラリは残存しているが、新規採用は不可能。[confidence: high — docs.cloud.google.com/translation-hub/docs/deprecations]

sokki での採用は完全に除外する。

---

## 3. Gemini API / Gemini 3.5 Live Translate

### 概要

2026年6月9日、Google は **Gemini 3.5 Live Translate** を Gemini Live API および Google AI Studio でパブリックプレビュー公開。音声→音声の End-to-End リアルタイム翻訳モデルであり、従来の ASR + MT + TTS チェーンとは根本的に異なるアーキテクチャ。[confidence: high — blog.google]

### 技術仕様

| 項目 | 仕様 |
|---|---|
| モデル名 | `gemini-3.5-live-translate-preview` |
| 入力フォーマット | Raw 16-bit PCM, 16kHz, mono, little-endian |
| 出力フォーマット | Raw 16-bit PCM, 24kHz, mono |
| チャンクサイズ | 100ms 単位 |
| 対応言語 | 70言語超 (自動検出) |
| レイテンシ | 数秒遅れ (near real-time) |
| プロトコル | WebSocket |

[confidence: high — ai.google.dev/gemini-api/docs/live-api/live-translate]

### 料金

| モデル | 入力 | 出力 | 実効単価 |
|---|---|---|---|
| `gemini-3.5-live-translate-preview` | $3.50/100万トークン (≈$0.0053/分) | $21.00/100万トークン (≈$0.0315/分) | **≈$0.037/分** |

音声は 25 tokens/秒 でカウント。60分会議では入出力合計で **≈$2.2/時間**。他の MT API の 7倍以上のコスト。[confidence: high — ai.google.dev/gemini-api/docs/pricing]

### sokki での評価

Gemini Live Translate は話者のイントネーション・テンポ・音調を保持して翻訳音声を合成するため、「翻訳字幕を表示する」という sokki の当面ユースケースには過剰。字幕のみ必要な場合は `inputAudioTranscription` + `outputAudioTranscription` でテキストを取得可能。現在はパブリックプレビューのため本番採用は慎重に。[confidence: high]

---

## 4. DeepL API

### テキスト翻訳 API

DeepL API Free は月500,000文字まで無料。DeepL API Pro は **$5.49 / 100万文字** (Google Translation v3 NMT の約1/4のコスト)。[confidence: high — buildmvpfast.com]

### DeepL Voice API (2026年2月ローンチ)

WebSocket ベースのストリーミング。tentative (暫定) + concluded (確定) セグメントを返す。推奨チャンクサイズ 50–250ms。PCM 16kHz または OPUS 32kbps に対応。[confidence: high — developers.deepl.com/api-reference/voice]

主な制約：
- ソース言語の明示が必要 (自動検出不可)
- 1セッションにつき翻訳ターゲットは5言語まで
- 公式 Swift SDK なし

### 日本語翻訳品質

DeepL は欧州語ペアで最高水準だが、**日本語については評価が分かれる**。日英・英日では Google Translate を上回るという評価も多い一方、東アジア言語ペア全般では Google Translation v3 と比較して優位が薄い。ビジネス会議の音声翻訳というユースケース (専門用語多め・口語) では Google v3 NMT のほうが安定性が高いと判断する。[confidence: medium — simplelocalize.io]

---

## 5. Apple Translation Framework (macOS 15+)

**sokki のローカル完結思想と最も相性が良い選択肢。無料・オンデバイス・プライバシー保護・ネットワーク不要。**

### 対応言語 (2026年6月時点)

**19言語**のみ。iOS 17 で Ukrainian、iOS 18 / macOS 15 で Hindi が追加。

英語 (US/UK) / 日本語 / 中国語 (簡体・繁体) / 韓国語 / アラビア語 / フランス語 / ドイツ語 / スペイン語 / イタリア語 / ポルトガル語 (BR) / ロシア語 / タイ語 / トルコ語 / ウクライナ語 / ベトナム語 / インドネシア語 / ポーランド語 / オランダ語 / ヒンディー語

SuperIntern の「50言語超」に対して大幅に少ない。[confidence: high — mjtsai.com / WWDC24]

### オフライン動作

Apple Neural Engine で処理。モデルはシステムの Translate アプリと共有。事前ダウンロード後はネットワーク完全不要。[confidence: high]

### API

`TranslationSession` がコアクラス。`translations(from:)` で `AsyncSequence` として結果を受け取る。リアルタイムのストリーミング翻訳はネイティブには非対応だが、WhisperKit の確定テキスト単位の送信で対応可能。[confidence: high — developer.apple.com/documentation/translation]

**注意:** Translation framework は Xcode Simulator および #Preview では動作しない。実機 Mac でのみテスト可能。[confidence: high]

---

## 6. 選択肢横断比較

| API | 言語数 | ストリーミング | コスト/1時間 | 日本語品質 | ローカル | 状態 |
|---|---|---|---|---|---|---|
| Apple Translation | 19 | 疑似対応 | **無料** | ◎ | 完全 | 安定 |
| Google Translation v3 | 135+ | 非対応 | ≈$0.30 | ◎ | なし | 安定 |
| Gemini 3.5 Live Translate | 70+ | 真のストリーム | ≈$2.20 | ◎ | なし | Preview |
| DeepL API Pro | 30+ | 非対応 | ≈$0.08 | ○〜◎ | なし | 安定 |
| DeepL Voice API | 30+ | WebSocket | 未公開 | ○〜◎ | なし | 安定 |
| ~~Google Media Translation~~ | — | — | — | — | — | **廃止 (2024/07)** |

---

## 7. パイプライン設計

### WhisperKit のストリーミング動作

argmax-oss-swift v1.0 (2026年5月) の WhisperKit は `SegmentDiscoveryCallback` によりリアルタイムでセグメントを通知。200–400ms 周期で partial results を UI に流せるよう抽象化されている。[confidence: high — github.com/argmaxinc/argmax-oss-swift]

### チャンク分割と部分確定テキストの扱い

翻訳 API へのリクエストは **確定セグメントのみ** に限定する。Partial transcript をそのまま翻訳すると API コールが爆発し、翻訳が揺れてユーザー体験が悪化する。

- **Partial テキスト** → 原文字幕としてリアルタイム表示、翻訳はスキップ
- **Confirmed セグメント** → 翻訳 API を非同期で呼び出し
- **翻訳完了後** → 翻訳字幕を差し替え表示 (原文と並列表示)
- **目標エンドツーエンド遅延:** 2–3秒

### 音声フォーマット

WhisperKit は 16kHz モノラル Float32 PCM を内部フォーマットとして使用。`AVAudioEngine` の出力を `AVAudioConverter` で変換してから渡す。

### 字幕オーバーレイウィンドウ

`NSWindow` の `level` を `.floating` に設定し、`isOpaque = false`、`backgroundColor = .clear` で透過常時最前面ウィンドウを実現。`ignoresMouseEvents = true` でクリックスルー。[confidence: high — Medium]

---

## 8. sokki 推奨構成 — ローカル優先 + API フォールバック (BYO Key)

### Tier 1: Apple Translation Framework (デフォルト・無料)

対応言語ペア (19言語内) は常にこれを優先。ユーザーが API Key を設定していない場合の唯一の選択肢。sokki の「ローカル完結」差別化を最もよく体現する。`SokkiKit` に `TranslationService` プロトコルを定義し、実装を差し替えられるよう抽象化する。

### Tier 2: Google Cloud Translation API v3 (BYO GCP API Key)

Apple Translation で未対応の言語ペア (19言語外) を自動的にこちらにルーティング。135言語超をカバー。コスト: $20 / 100万文字。会議1時間 ≈ **$0.30**。REST 実装なので依存ライブラリ追加不要。

### 将来 Option: Gemini 3.5 Live Translate

翻訳音声読み上げ機能を追加する場合に優位。コストが高い ($2.2/時間) ため Phase 3 以降に GA 後再評価。

### 除外: DeepL API

言語数 (30言語) が Google v3 (135言語) に劣り、日本語での優位性も不明確。BYO Key ユーザーに「GCP Key か DeepL Key か」を選ばせる UI コストのほうが高い。

### 料金試算 — 月40時間使用の場合

| 項目 | 費用 |
|---|---|
| Apple Translation (Tier 1、約80%カバーと仮定) | $0 |
| Google Translation v3 (残り8時間 × 15,000文字/時間) | ≈$0.024 |
| **ユーザー負担合計** | **≈$0.024/月** |
| sokki 運営コスト | **$0** |

### Phase ロードマップ

- **Phase 2**: Apple Translation + 字幕オーバーレイ実装
- **Phase 3**: Google Translation v3 BYO Key + 135言語拡張
- **Phase 4**: Gemini 3.5 Live Translate (翻訳音声機能) — GA後検討
