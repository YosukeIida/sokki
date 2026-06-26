# SuperIntern 完全調査レポート（clone 構築仕様）

> 調査方法: 8 方面（Product Hunt / 公式サイト / 価格 / 技術スタック / UI/UX / 機能深掘り / 評判 / 企業背景）を sonnet エージェント並列で web 調査し統合。
> 調査日: 2026-06-25 / 各事実に `[confidence: high/medium/low]` と出典を併記。**【推定】** は推測であり一次裏付けがない。
> 関連: [`superintern-feature-plan.md`](./superintern-feature-plan.md)（sokki への取り込みプラン・先行版）

---

## 1. エグゼクティブサマリー

SuperIntern は **NanoHuman 株式会社**（2025-03-27 設立・東京都中央区晴海、CEO 伊藤工太郎 / Etaro Ito）が開発する macOS（後に Windows）向けの **ボットレス会議 AI アシスタント**。会議プラットフォームに bot を参加させず、OS のシステム音声とマイクを直接キャプチャして、リアルタイム文字起こし・**50 言語以上のリアルタイム双方向翻訳字幕**・**AI Canvas（テンプレート駆動のライブ議事録）**・会議中/後の AI チャットを提供する。Zoom・Google Meet・Teams・Slack Huddle・Webex・対面会議すべてで動作し、参加者からは不可視（Invisible Mode）。Product Hunt で複数回ローンチし 2025-11-29 に「#5 Product of the Day」を獲得したが、第三者の独立レビューはまだ少なく市場浸透は初期段階。ASR/翻訳/LLM の具体的なエンジンは非公開だが、プライバシーポリシーのサブプロセッサーに **OpenAI と Google** が明記されており、クラウド AI 推論に依存している。

---

## 2. プロダクト概要

| 項目 | 内容 | confidence |
|---|---|---|
| 形態 | macOS デスクトップアプリ（Apple Silicon M1+ 推奨）。Windows 版は Microsoft Store（アプリ ID `9pnv1c3jmfrc`）で 2026-05-12 提供開始 | high |
| コア価値 | 「bot を呼ばずに」あらゆる会議で議事録・翻訳・要約・Q&A を自動化 | high |
| 対象ユーザー | PM・セールス・HR 面接・コンサル・CS・デザインレビュー・経営会議・多言語/グローバル会議・対面会議 | high |
| 看板差別化 | ① ボットレス（システム音声直接キャプチャ）② 50 言語リアルタイム翻訳 ③ AI Canvas ④ クロスミーティング AI チャット ⑤ Invisible Mode | high |
| 会社ミッション | "Build Tools for AGIs"（nanohuman.ai） | high |

---

## 3. 機能インベントリ

| 機能 | 入力 → 出力 / 挙動 | confidence | 出典 |
|---|---|---|---|
| ボットレス音声キャプチャ | システム音声（スピーカー出力）＋マイク → 音声ストリーム。bot 不参加・プラグイン不要・参加者から不可視 | high | 公式 / PH |
| 対応会議プラットフォーム | Zoom・Google Meet・Teams・Slack Huddle・Webex・対面。会議開始を自動検出しポップアップ、ワンクリックで録音開始 | high | 公式 |
| リアルタイム文字起こし | 音声 → テキストストリーム（話者分離付き）。文字起こし停止を検知し自動復旧（Watchdog） | high | v0.13 |
| リアルタイム翻訳字幕 | 音声 → 原語＋翻訳のデュアル字幕。50 言語超、双方向、言語自動検出、遅延 3 秒未満。TTS 出力は無し（字幕のみ） | high | /translation |
| 翻訳モード切替 | `Transcribe`（文字起こしのみ）/ `Translate To`（一方向）/ `Translate Between`（双方向 2 カラム）をワンクリック切替 | high | v0.12 |
| 言語の独立設定 | 音声・字幕・サマリーの言語を別々に設定可（例: 日本語音声→日英字幕→英語サマリー） | high | blog |
| AI Canvas（ライブ議事録） | テンプレート（指示文）＋会議音声 → 構造化 Markdown ノートをリアルタイム差分更新（変化した見出し/箇条書き/表のみ再生成） | high | v0.14 |
| AI Canvas テンプレート | 「役割／出力形式／背景情報」の 3 要素。`{{...}}`=毎回の背景情報、`{...}`=AI 記入欄。会議タイプ別に複数保存、開始前に選択。標準サンプル 5 種（日次スタンドアップ・1on1・候補者面接・カスタマーディスカバリー・セールスコール） | high | blog |
| 会議中 AI チャット | 進行中の会議文脈を参照しリアルタイム Q&A | high | 公式 |
| クロスミーティング AI チャット | 過去会議を横断検索・引用・推論。回答にソースバッジ（該当会議/箇所へジャンプ）。Thinking UI で検索過程を表示。同一スレッドで文脈記憶（fast follow-ups） | high | v0.13 |
| 会議後サマリー | 会議終了直後（3 秒以内）にストリーミング生成。話者名インライン編集→トランスクリプト/参加者へ自動同期 | high | v0.11/v0.13 |
| 話者識別（diarization） | v0.10 で AI 自動識別。v0.13 で Google Calendar 出席者数から話者数を自動導出し精度向上。`Analyze speakers` で話者数 1〜30 入力→発言比率表示→名前手動編集 | high | v0.10/v0.13 |
| カスタム辞書 | 企業名・人名・製品名・専門用語を登録し精度向上。CSV 一括インポート対応、チーム共有可 | high | weekly |
| 音声ファイルアップロード | mp3/m4a/wav 等 → 事後に文字起こし・話者分離・サマリー・Canvas ノート生成 | high | weekly |
| エクスポート | Markdown（ワンクリック・話者帰属/アクション付き）・プレーンテキスト・クリップボード。PDF は言及あるが確証低 | high(md) / low(pdf) | v0.11 |
| 共有リンク | サマリーのみ or トランスクリプト+録音を選択して共有。個人情報（メール/ID）は共有ビューから自動削除 | high | v0.12 |
| Invisible Mode | 画面共有/スクショ時に SuperIntern の UI を他参加者から不可視化 | high | blog |
| Google Calendar 連携 | 会議自動検出・管理、話者数推定、Meet の Chrome プロファイル自動判定 | high | v0.12 |
| Web アプリ | ブラウザからトランスクリプト/サマリー/ノート閲覧（デスクトップ・モバイル） | high | v0.12 |
| グローバル検索 | `Cmd+K`/`Ctrl+K` で全会議をキーワード検索しジャンプ | high | weekly |
| Projects | 会議をイニシアチブ/クライアント/テーマ別にグループ化。最大 50 件一括インポート、AI が関連会議を提案 | high | v0.14 |
| ノイズ抑制 | v0.9 でノイズキャンセル＋エコー除去、v0.12 で追加改善（ライブラリ名非公開） | medium | blog |
| MCP 自動化（開発中） | Model Context Protocol で会議後に外部ツール/エージェントを自動操作（2025-12 時点で開発中ステータス） | high | PH |
| Team 機能 | Team Space 共有・Projects 権限制御・Private Folder・一元請求・使用量ダッシュボード | high | blog |

---

## 4. 技術アーキテクチャ推定（最重要）

> ⚠️ **エンジンの固有名は公式が一切非公開。** 以下は条件適合とプライバシーポリシーのサブプロセッサーからの推定を含む。

### 4.1 サブプロセッサー（一次情報・nanohuman.ai/privacy）

| ベンダー | 用途 | confidence |
|---|---|---|
| **OpenAI, L.L.C.** | テキスト/音声推論 | high |
| **Google LLC** | テキスト/音声推論・cookie・分析 | high |
| AWS（日本・米国リージョン） | クラウドインフラ | high |
| Vercel | ホスティング | high |
| Stripe | 決済（トークン化） | high |
| Mux | 動画ホスティング | high |

→ ASR・LLM・翻訳のいずれも **OpenAI または Google のクラウド API** に依存している可能性が高い。両方が「音声推論」として登録されているため、どちらが ASR でどちらが LLM かは特定不能。**オフライン動作は非対応と推定。**

### 4.2 各レイヤーの推定

| レイヤー | SuperIntern の推定 | confidence | sokki での対応方針 |
|---|---|---|---|
| 音声キャプチャ | **Core Audio Taps API（macOS 14.4+）** が「ドライバ不要・システム全音声タップ」に唯一合致。ScreenCaptureKit も候補 | medium | sokki も同方針（D-9: Phase1 AVAudioEngine→Phase2 SCStream）。Core Audio Taps を再検討の価値あり |
| 文字起こし | OpenAI or Google のクラウド ASR | high(クラウド) / low(特定) | **sokki は WhisperKit オンデバイス ASR を維持 → これが最大の差別化** |
| 翻訳 | 非公開（OpenAI/Google/DeepL のいずれか） | low | DeepL API（日本語品質）or OpenAI Realtime（ASR+翻訳同時）が候補 |
| 話者識別 | AI 駆動 + Calendar 出席者数ヒント | high(挙動) / low(実装) | sokki は SpeakerKit（Phase3）+ 声紋永続記憶で上回れる |
| LLM（議事録/チャット） | OpenAI GPT 系 or Gemini 系 | low | Gemini Flash or ローカル LLM（設定切替） |
| アプリ実装 | **Windows 対応の実績から Electron または Tauri が有力**（ネイティブ Swift では Win 非現実的） | medium | **sokki はネイティブ SwiftUI → macOS 体験で差別化（ただし Win 非対応がトレードオフ）** |

### 4.3 参照実装

- **Recap**（github.com/RecapAI/Recap・オープンソース macOS）= Swift + SwiftUI + **Core Audio Taps** + AVAudioEngine + **WhisperKit**（ローカル文字起こし）+ Ollama。**sokki の技術構成とほぼ同一**で、ボットレス方式の参照実装として最有用。`[confidence: high]`

### 4.4 リアルタイム翻訳パイプライン（推定）

```
音声キャプチャ → ASR（音声認識）→ MT（機械翻訳）→ デュアル字幕表示
                                              遅延 < 3 秒
```
- 字幕形式のみ（音声合成 TTS は無し）`[confidence: medium]`
- スクリーン共有時はステルスモードで字幕オーバーレイを非表示 `[confidence: high]`

---

## 5. UI/UX 仕様（画面起こし可能な粒度）

### 5.1 全体構造（3 レイヤー）
1. **コントロールバー** — 録音操作・オーディオデバイス切替・ショートカットピッカー・カスタム辞書語数表示・テンプレート切替・一時停止/再開
2. **AI Canvas パネル** — リアルタイム構造化ノート（差分更新）
3. **字幕オーバーレイ** — 翻訳字幕（3 モード切替・双方向時は 2 カラム）

### 5.2 オンボーディング
ダウンロード → アカウント作成 → 言語・オーディオソース設定（公称「5 分未満」）`[medium]`。権限許可ダイアログ（マイク/画面キャプチャ）の詳細順序は **未確認**。

### 5.3 会議中
- 会議自動検出ポップアップ → ワンクリック録音開始
- AI Canvas が選択テンプレートに沿ってリアルタイム記入（差分のみ更新）
- 翻訳字幕（`Transcribe` / `Translate To` / `Translate Between`）
- AI チャットパネル（クイックアクションボタン付き）
- Invisible Mode トグル
- 録音一時停止/再開

### 5.4 会議後（詳細画面）
- タブ: **Summary / Transcript / Notes(AI Canvas)** の最低 3 タブ
- `Cmd+F` ページ内検索（全マッチ強調）
- Transcript: セグメントクリックで該当録音箇所から再生、`Analyze speakers` で話者分離画面
- サマリー項目クリックで録音タイムスタンプにジャンプ（ホバープレビュー）
- AI チャット: `Follow-up` でフォローアップメール自動生成、`Skills` で頻用プロンプト保存、`Esc` で生成停止
- エクスポートボタン（Markdown/Text/コピー）、共有リンク生成
- AI 出力は character-by-character の blur-in アニメーションでストリーミング表示

### 5.5 ホーム/設定
- ホーム: Google Calendar 連携で当日・今後の会議一覧（カレンダー色分け）
- 設定: カレンダー接続・使用量プログレスバー・カスタム辞書（CSV インポート）・Instruction テンプレート管理
- Team: Members タブ（Admin/Member ロール・招待追跡）・集約請求・複数管理者

### 5.6 未確認の UI 詳細
字幕オーバーレイの正確な位置/ドラッグ可否/フォント設定、コントロールバーの寸法・ボタン配置、会議一覧のリスト/カード形式、メニューバー常駐 or 独立ウィンドウ、ログイン画面の OAuth 連携先。

---

## 6. 価格・ビジネスモデル

| プラン | 価格 | 上限/内容 | confidence |
|---|---|---|---|
| Free | $0 | 全機能利用可・**利用時間に上限**（一説: 1 録音 3 分・月 120 分）。クレカ不要 | high(無料) / medium(上限値) |
| Plus | **$20/月** | 100 時間/月、超過 **$0.02/分**。全機能 | high |
| Team | **$35/ユーザー/月** | メンバー数×100 時間、Team Space 共有・権限管理 | high |
| Enterprise | 要問合せ | SSO・監査ログ・データ保持・ZDR・優先サポート | high |

- 課金モデル = **サブスク＋超過従量のハイブリッド**。BYO API キーは確認されず。`[medium]`
- 旧体系（2025-08 PR）: On Demand $0.10/分・Plus $30/月 30h → 現行へ値下げ・時間増。`[high]`
- 日本円旧価格: Plus ¥3,300/月 50h・超過 ¥2/分 → **地域別価格の可能性**。`[medium]`
- 年額プラン・返金/解約条件は公式に **明記なし**。
- 競合価格: Otter Pro $16.99 / Notta Pro $14.99 / tl;dv Pro $18 / Fathom $19 / Tactiq $8-12 / Circleback $25。SuperIntern は中〜高価格帯だが「ボット不要＋翻訳」で差別化。`[medium]`

---

## 7. 企業背景・ローンチ時系列

| 項目 | 内容 | confidence |
|---|---|---|
| 開発会社 | NanoHuman 株式会社（2025-03-27 設立、東京都中央区晴海 5-3-2） | high |
| CEO | 伊藤工太郎 / Kotaro(Etaro) Ito（X: @etaroid）。LayerX 出身、19 歳起業経験 | high |
| PH クリエイター | Kazuki Senkoji（PH 担当 or 別メンバー、役割分担は不明） | medium |
| SNS | X @NanoHumanAI / LinkedIn /company/nanohuman / GitHub @NanoHuman | high |
| 資金調達 | **公開情報なし**。YC 等の参加も確認できず。East Ventures とポッドキャスト共同運営の縁はあるが投資は未確認 | high(なし) / medium(EV) |
| Discord/コミュニティ | 確認できず | medium |

**時系列**: 2025-04-16 PH 初ローンチ(13票) / 2025-08-21 Mac 版一般公開 / 2025-10-26 v0.3(119票) / 2025-11-23 Translation(102票) / 2025-11-29 Always-on Meeting AI(138票・#5) / 2026-04-21 v0.14(AI Canvas) / 2026-05-12 Windows 版 / 2026-06-17 Team プラン。**月 1〜2 回ペースで活発に開発中。**

---

## 8. 評判・強み・弱み

### 8.1 受容
- Product Hunt: 累計 420 upvotes・42 comments・#5 of the Day（2025-11-29）。ただし**製品ページのユーザーレビューは 0 件**。`[high]`
- 日本語 X で「UX がマジで神」等の好意的言及あり（投稿主の独立性は不明）。`[medium]`
- 大手レビューサイト（meetingnotes.com Top10 / timingapp.com 等）に**未掲載**＝認知度は初期段階。`[high]`

### 8.2 弱み（clone する側の攻めどころ）
- MCP/Automation Skills が開発中（会議後ワークフロー自動化・CRM 連携が未成熟）`[high]`
- 話者識別が Calendar 連携前提で精度が出る `[high]`
- セキュリティ詳細が不透明（独立監査の証拠なし、SOC 2 Type 2 は 2026 秋取得予定）`[high/medium]`
- 騒音・複数同時発話・皮肉の誤認識（公式も認める）`[high]`
- モバイル非対応（Mac/Win デスクトップのみ）、オフライン録音/ポータブル不可 `[high]`
- 会社が新興（2025 設立）で長期信頼性の実績が浅い `[high]`

### 8.3 強み（再現すべき点）
ボットレス × リアルタイム翻訳（50 言語）の組み合わせが最大の独自性。Granola など競合にない翻訳機能。AI Canvas の差分更新 UX とクロスミーティングチャットの引用 UX が完成度高い。

---

## 9. clone 実装ロードマップ（sokki の既存資産前提）

> sokki = ネイティブ SwiftUI + SwiftData + WhisperKit。**「オンデバイス ASR + 声紋永続記憶 + ネイティブ macOS 体験」で SuperIntern を上回る**方向が差別化として有効。

| Phase | 取り込む機能 | 主要実装 | 既存資産 |
|---|---|---|---|
| **Phase 1（現在）** | 録音・文字起こし・一覧/詳細・Markdown エクスポート | AVAudioEngine + WhisperKit | 実装済み（Issue #2-5） |
| **Phase 2** | システム音声キャプチャ・リアルタイム字幕・**リアルタイム翻訳** | SCStream または Core Audio Taps、`GeminiLiveTranslateClient.swift` / `AudioConverter.swift`（feature-plan 参照）、`LiveTranscriptView` 翻訳レーン | feature-plan に設計あり |
| **Phase 3** | 話者分離＋**声紋永続記憶**（独自強み） | SpeakerKit + `SpeakerProfileStore` | spec D 系で設計済み |
| **Phase 4** | AI Canvas（テンプレート駆動ライブ議事録）・会議後サマリー | テンプレート定義（役割/出力形式/`{{}}`/`{}`）＋差分更新ロジック＋ LLM | 新規 |
| **Phase 5** | 会議中/クロスミーティング AI チャット・カスタム辞書・共有・Projects・Invisible Mode | `SessionDetailView` に AI タブ、`AppSettingsModel` 拡張、`NSPanel.sharingType = .none` | 新規 |

### 9.1 clone に直結する技術的勘所
- **Invisible Mode**: `NSPanel.sharingType = .none` で ScreenCaptureKit のキャプチャ対象から自ウィンドウを除外。`[実装方針]`
- **音声キャプチャ**: Core Audio Taps API（macOS 14.4+、ドライバ不要）を Recap 実装が証明済み → sokki の Phase2 で SCStream と比較検討。
- **AI Canvas 差分更新**: 全文再生成せず「変化した見出し/箇条書き/表のみ」を更新する設計が UX 鍵。
- **翻訳**: DeepL API（日本語品質・REST 容易）or OpenAI Realtime（ASR+翻訳同時処理）。

---

## 10. 未解明点・要追加調査リスト

1. **エンジン特定不能**: ASR（Whisper/Apple/Deepgram/Google）・翻訳（DeepL/Google/OpenAI）・LLM（GPT/Gemini/Claude）すべて非公開。OpenAI と Google 両方がサブプロセッサーのため切り分け不可。
2. アプリ実装フレームワーク（Electron / Tauri / ネイティブ）の確証（Win 対応から Electron/Tauri 推定）。
3. 音声キャプチャの具体 API（Core Audio Taps か ScreenCaptureKit か）。
4. オフライン処理 vs クラウド送信の比率・バッファリング・データ保持の詳細。ZDR の対象プロバイダ。
5. Free プランの正確な時間上限（「3 分/回・120 分/月」説と「フル会議長で試用可」説が混在）。
6. 年額プラン・返金/解約条件・Enterprise 価格水準。
7. カスタム辞書の上限件数、クロスミーティングチャットの横断会議数/トークン上限。
8. 字幕オーバーレイ・コントロールバー・会議一覧の正確な UI レイアウト。
9. Notion/Slack 連携の実装方式（OAuth Push / Webhook / コピー）。
10. 第三者の定量ベンチマーク（WER/BLEU）が存在せず「高精度」主張は未検証。
11. 資金調達の有無、ユーザー数/MRR 等のビジネス指標。

### 追加調査の手段（必要なら）
- **実機検証**: 無料プランをダウンロードし、Charles/Proxyman で通信先ドメインを観測 → ASR/翻訳の API エンドポイント特定（最も確実）。
- バイナリの `otool -L` / `strings` で依存フレームワーク（WhisperKit/Electron 等）を確認。
- `nanohuman.ai/privacy` のサブプロセッサー更新を定期チェック。

---

## 付録: 主要出典

- 公式: https://super-intern.com/en（/translation, /pricing, /blog/v0-9〜v0-14update, /blog/2026-* 各記事）
- 法務/会社: https://www.nanohuman.ai/privacy（サブプロセッサー）, /legal/tokushoho
- Product Hunt: https://www.producthunt.com/products/superintern , /p/superintern
- PR: prtimes.jp/main/html/rd/p/000000001〜006.000168239.html
- 参照実装: https://github.com/RecapAI/Recap
- 統合レポート（Artifact 版・同一内容のリッチ版）: https://claude.ai/code/artifact/8549934e-0707-4f94-844e-2eb464338a22
