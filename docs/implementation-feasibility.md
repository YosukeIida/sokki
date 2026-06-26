<!-- sokki 調査ドキュメント / 生成: 2026-06-26 / 実装可能性・完全書き換え可否の評価 -->
# sokki 実装可能性 評価レポート

> 評価者: テックリード / 作成日: 2026-06-26
> 対象: `/Users/yosuke/workspace/github.com/YosukeIida/sokki`（main, HEAD 03ab9b0）
> 一次資料: 実コード Read（Sources/SokkiKit 全体）、spec.md、requirements.md、docs/superintern-feature-plan.md、Recap copy 抽出、外部 OSS/翻訳/話者分離調査

---

## 0. 結論（先に要点）

- **現状の sokki は「Phase 1 MVP の骨格＋差別化機能の型定義」が揃った状態。** 抽象境界（`TranscriptionEngine` / `DiarizationEngine` protocol、actor 分離、`@ModelActor`、DI コンテナ）は spec どおり丁寧に切られており、**Recap の知見を流し込む受け皿がすでに正しい形で存在する**。
- ただし**「動くのはマイク録音→バッチ文字起こし→SwiftData 保存→Markdown コピー」までで、それ以外は配線されていない**。システム音声・リアルタイム・話者分離・声紋・翻訳・音声ファイル保存・再生は **未実装 or 型だけ**。
- **重大な事実上のギャップ**: コードベースに `AVAudioFile` / `.write(from:)` の呼び出しが **1 箇所も無い**（grep 確認済み）。`SessionModel.audioFilePath` はパスを生成するだけで**音声ファイルは一切ディスクに書かれていない**（= Issue #4 未着手、再生機能の前提が無い、Recap 流ファイルパイプラインに直結する課題）。
- **「今回の調査資料だけでフルスクラッチ再構築できるか」への答え: できない。そして、する必要もない。** Recap 抽出は copy レベルで精度が高く音声系は全面流用に足るが、(a) 実バイナリ未取得・(b) WhisperKit/SpeakerKit の v1.0 実 API（streaming・embedding 取り出し）が未確認・(c) 翻訳が外部 API 依存で要実証、の 3 点で「白紙から一気通貫」は不可。**既存の良い抽象を土台にした増分実装を強く推奨**（理由は §5）。

---

## 1. 現状 sokki 実装度サマリー（ファイル単位・事実ベース）

凡例: ✅実装済み（動作経路あり） / 🟡骨格のみ（型・スタブ・一部 TODO） / ⛔未着手（参照されない/将来用）

| ファイル | 状態 | 事実根拠 |
|---|---|---|
| `Audio/AudioCaptureManager.swift` | 🟡 | マイク（AVAudioEngine→AVAudioConverter で16k/mono/Float32）は実装済。**`mode != .micOnly` は `throw systemAudioRequiresPhase2`**。systemStream/systemLevel は生成のみで未配線（`_ = sysLvlCont`）。AVAudioFile 書き出しなし。 |
| `Audio/PermissionManager.swift` | ✅ | マイク権限のみ。Screen Recording / 通知権限は無し。 |
| `Transcription/TranscriptionEngine.swift` | ✅ | protocol 定義は完結。`isConfirmed` / hypothesis を含む良い抽象。 |
| `Transcription/WhisperKitEngine.swift` | 🟡 | バッチ `transcribe(audioArray:)` は実装・特殊トークン除去あり。`transcribeStream` は**自前 30s 窓＋5s overlap の擬似ストリーミング**で、生成 segment は全て `isConfirmed: true`（= 真の hypothesis/confirmed 2 ストリームではない）。WhisperKit の `LiveTranscriber` は未使用。 |
| `Transcription/TranscriptionPipeline.swift` | 🟡 | `@Observable @MainActor`。start/stop・タイマー・confirmed 蓄積・逐次 appendSegment は動く。`.both` は「TODO: ストリームマージ」で**実質マイクのみ**。`mode==.systemOnly/.both` は capture 層で throw されるため UI で無効化。diarization は `// Phase 3 で` のコメントのみ。 |
| `Diarization/DiarizationEngine.swift` | ✅(型) | protocol＋`DiarizationSegment.embedding: [Float]?` まで定義済み。 |
| `Diarization/SpeakerKitEngine.swift` | 🟡 | `SpeakerKit()` 生成・`diarize` 呼び出しは記述済み。だが **`embedding: nil`（「SpeakerKit は埋め込みを直接公開しない」とコメント）**。**パイプラインから一度も呼ばれていない**（TranscriptionPipeline に diarization 呼び出しが無い）。 |
| `SpeakerProfile/SpeakerProfileStore.swift` | 🟡 | findOrCreate / EMA 更新 / 集約平均→L2 正規化まで実装。ただし入力 `DiarizationResult.embedding` が常に nil なので**実データでは空回り**。呼び出し元なし。 |
| `SpeakerProfile/EmbeddingMatcher.swift` | ✅ | vDSP コサイン類似度・L2 正規化。**テスト済み（EmbeddingMatcherTests）**。差別化機能の中で唯一“実証済み”の部品。 |
| `Session/SessionManager.swift` | ✅ | `@ModelActor`。create/append/updateDuration/assignSpeakers/delete/各 count。設計どおり PersistentIdentifier 越境。 |
| `Models/*` (Session/Segment/SpeakerProfile/AppSettings) | ✅ | spec と一致。`embeddingData: Data`、`[Float]↔Data`、`@Relationship` 整合。 |
| `Export/ExportService・Markdown・SRT・VTT・PlainText` | ✅ | 全形式実装。**ExportTests 通過**。SRT/VTT も既に完成（spec 上は Phase4 だが先取り済み）。 |
| `LLM/OpenAICompatClient.swift` | 🟡 | chat/completions・話者名推定・要約は実装。**どこからも呼ばれていない**。Keychain 連携なし（API キーは AppSettings に平文）。 |
| `App/AppDependencyContainer.swift`・`AppFactory.swift`・`sokki/App/sokkiApp.swift` | ✅ | 手製 DI（Recap の DependencyContainer と同思想）。ModelContainer 生成・environment 注入・Settings シーンまで配線。 |
| `UI/ContentView`（NavigationSplit） | ✅ | 録音 / 一覧 / 話者プロファイルの 3 導線。 |
| `UI/RecordingView` | ✅(MVP) | Mic 録音ボタン・経過時間・ローディング・エラーバナー・権限チェック。**System/Both は `disabled: true`（"Phase 2 で実装予定"）**。 |
| `UI/LiveTranscriptView`・`SessionListView`・`SessionRowView`・`SegmentListView`・`SessionDetailView`・`SpeakerProfileView` | ✅(骨格) | 表示・エクスポートメニュー（クリップボードコピー）まで。`SessionDetailView` に音声**再生 UI は無い**（AudioPlaybackController は spec に名前があるだけで未作成）。 |
| `UI/WaveformView`・`LevelMeterView` | 🟡 | View 自体は実装済みだが levelStream の供給元（system 側）が無く、Phase 2 用の置き石。 |
| `Mocks/PreviewMocks` + Tests（20件） | ✅ | EmbeddingMatcher / Export / MockTranscription / Snapshot。実エンジン（WhisperKit/SpeakerKit）を起動する統合テストは無い。 |

**サマリー**: 「アーキテクチャの背骨」と「Phase 1 の文字起こし経路」と「Export」は本物。**差別化機能（声紋）・システム音声・リアルタイム・翻訳・音声ファイル I/O は“配線されていない型”**。

---

## 2. 機能別 実装レディネス表

判定: 🟢いますぐ実装可能 / 🟡追加調査要 / 🔴ブロッカーあり

| 機能 | 判定 | 根拠（sokki 現状＋Recap/調査） | 参照 Recap/OSS コンポーネント |
|---|---|---|---|
| **システム音声キャプチャ** | 🟢 | sokki は `AudioLane.system`/`systemStream` の型を既に持つ。Recap 抽出が **ProcessTap の 10 ステップ＋Aggregate Device 辞書（`kAudioSubTapUIDKey` に `tapDescription.uuid.uuidString` を渡す“最大のはまりどころ”含む）** を copy レベルで提供。MIT で流用可。唯一の前提作業は entitlement（後述）。 | `ProcessTap.swift`, `ProcessTapRecorder`, Apple WWDC24 公式サンプル（法的に最も安全な一次ソース） |
| **デュアル録音（system＋mic 同時）** | 🟢 | sokki は mic 側 AVAudioEngine が動作済み。Recap の `AudioRecordingCoordinator` が**起動順序の依存（system 先 → tapStreamDescription 確定 → mic を targetFormat 付きで起動）**と stop 逆順を明示。sokki の `.both`（現在 TODO）はこの設計をそのまま移植すれば閉じる。 | `AudioRecordingCoordinator`, `MicrophoneCapture`, `RecordingConfiguration` |
| **リアルタイム文字起こし** | 🟡 | sokki の `transcribeStream` は擬似窓方式で “確定/仮”の区別が無い。spec は LiveTranscriber 前提だが、**WhisperKit v1.0 の streaming/確定境界 API のシグネチャが実機未確認**。Recap も実は**バッチ（`whisperKit.transcribe(audioPath:)`）でタイムスタンプ/話者を捨てている**ため、リアルタイムの参照実装は Recap には無い。 | OSS: WhisperAX（argmax 公式 streaming 例）, OpenSuperWhisper |
| **会議自動検出** | 🟢 | sokki には未着手だが完全に独立サブシステム。Recap 抽出が **`MeetingDetectionService`（1s Task.sleep ポーリング）＋`SCShareableContent.current`＋bundleID フィルタ＋`MeetingPatternMatcher`（正規表現不使用の contains）** を全部出している。`SCShareableContent` は**画面収録 entitlement 不要**（throw で権限検知）なのが効く。 | `MeetingDetectionService`, `Zoom/Teams/GoogleMeetDetector`, `MeetingPatternMatcher` |
| **処理パイプライン（録音後バッチ）** | 🟢 | sokki は pipeline.stop() でフラッシュ→保存まで動く。Recap の **`ProcessingCoordinator`（AsyncStream 直列キュー＋`await processingTask?.value` で直列保証）と DB 永続化状態 enum** をそのまま採用すると、Issue #3（durationSeconds）・スリープ復帰・キャンセルが体系化できる。要約フェーズは**ゲートで省略可**（`completeProcessingWithoutSummary` パスが存在）と確認済み。 | `ProcessingCoordinator`, `RecordingProcessingState`, `SystemLifecycleManager` |
| **話者分離** | 🔴→🟡 | sokki の `SpeakerKitEngine` は `embedding: nil`。**声紋永続記憶（最大の差別化）に必須の embedding 取り出しが、SpeakerKit v1.0 で公開されているか未確認＝現状ブロッカー**。調査で **FluidAudio は `extractEmbedding()` が public（256次元 L2 正規化済み）で sokki の SpeakerProfileStore 設計と完全一致**と判明 → エンジン差し替えで解除可能（D-5 の protocol 化が効く）。日本語 DER は Pyannote community-1=28.8% に対し Sortformer=12.7%。 | argmax SpeakerKit（統合最易）/ **FluidAudio（embedding 確実・推奨）** / WhisperX（マージ参照） |
| **リアルタイム翻訳** | 🟡 | sokki に翻訳コードは皆無（grep 0 件）。docs/superintern-feature-plan は Gemini Live Translate（WebSocket, 16k PCM, 100ms）を想定し**sokki の 16k mono と整合**するが、**(a) Gemini 3.5 Live はパブリックプレビュー、(b) SuperIntern の MT エンジンは推定（確率60-70%）で未確証、(c) ≈$2.2/時とコスト高**。字幕用途なら Apple Translation（19言語・無料・オンデバイス）が思想的に最適だが言語数が SuperIntern の主張に届かない。**方式選定に追加実証が必要**。 | 調査: Gemini Live Translate / DeepL Voice / Apple Translation Framework |
| **エクスポート** | 🟢 | **既に完成・テスト通過**（Markdown/SRT/VTT/Plain）。残るは「ファイル保存ダイアログ＋Security-Scoped Bookmark」だけ（現状クリップボードコピーのみ）。Recap も「パスを文字列 DB 保存」で、sokki では Bookmark 化推奨。 | （sokki 自前で完了）/ Recap の Sandbox + Bookmark 注意 |

---

## 3. Recap → sokki コンポーネント対応表

| Recap のファイル/パターン | 対応する sokki ファイル | 移植アクション |
|---|---|---|
| `ProcessTap.swift`（CATapDescription→Aggregate→IOProc, dBFS ピークメータ） | `Audio/AudioCaptureManager.swift`（system レーン部） | **新規追加**: `ProcessTap` を内包し `systemStream`/`systemLevelStream` を配線。`startCapture(.systemOnly/.both)` の throw を撤去。 |
| `MicrophoneCapture+AudioEngine.swift`（inputNode→mixer→tap, AVAudioConverter） | 既存 `startMicCapture()`（ほぼ同等の実装が**すでに存在**） | 移植不要。Recap の pre-warm（init で AVAudioEngine 事前準備）だけ任意採用。 |
| `AudioRecordingCoordinator.swift`（起動順序・stop 逆順） | `Transcription/TranscriptionPipeline.swift` の `.both` 分岐（現 TODO） | **新規追加**: mic/system 2 ストリームの同期起動・停止ロジック。 |
| `RecordingConfiguration` / `RecordedFiles`（baseURL→.system.wav/.microphone.wav） | `Session/SessionManager.makeAudioFilePath()`＋（新規）AudioFileWriter | **新規追加**: 現状欠落の AVAudioFile 書き出しをここで実装（Issue #4）。 |
| `ProcessingCoordinator.swift`（AsyncStream 直列キュー） | `TranscriptionPipeline`（または新規 `ProcessingCoordinator`） | **新規追加 or 拡張**: 録音後バッチ処理（duration 更新・diarization 実行・声紋解決）を体系化。 |
| `RecordingProcessingState`(Int16 rawValue, summarizing/failed) | `SegmentModel`/`SessionModel` には state 無し | **任意追加**: 大規模化したら導入。要約系の値(4,7)は欠番に。 |
| `WhisperKit+ProgressTracking.swift`（download/init 分離・進捗・getModelSizeInfo） | `Transcription/WhisperKitEngine.prepare()`（進捗なし） | **拡張**: モデル DL 進捗 UI（現状は loadingMessage 固定文字列のみ）。 |
| `WhisperModelRepository`（Core Data, isDownloaded/isSelected バリデーション） | `Models/AppSettingsModel.whisperModelVariant`＋`SettingsView` Picker | **任意**: 現状は Picker 直書きで足りる。モデル管理 UI を作るなら参照。 |
| `MeetingDetectionService` ＋各 Detector ＋ `MeetingPatternMatcher` | （sokki に該当無し） | **新規サブシステム**として丸ごと追加（要約非依存で安全）。 |
| `DependencyContainer`（lazy var＋extension 分割、inMemory 切替） | `App/AppDependencyContainer.swift`（既に同思想・小規模） | 思想一致。肥大化時に extension 分割を踏襲。 |
| Core Data Repository（`performBackgroundTask`＋continuation→DTO 変換） | `@ModelActor SessionManager`＋`SpeakerProfileStore` | sokki は SwiftData で**より単純化済み**。Recap の DTO 越境思想だけ踏襲（PersistentIdentifier 既採用）。 |
| `PermissionsHelper`（mic/screen/notification, `SCShareableContent` で権限検知） | `Audio/PermissionManager.swift`（mic のみ） | **拡張**: screen-capture / notification を追加。 |
| `StatusBarManager`/`SlidingPanel`/`PanelAnimator`（メニューバー常駐） | （sokki は WindowGroup の通常アプリ） | **任意・要 UX 判断**: SuperIntern 風フローティング字幕を作るなら参照。現 sokki の方針とは別路線。 |
| `TranscriptionService.buildCombinedText`（`[User Audio Note]` 注入） | — | **採用しない**（要約用の連結。sokki は要約不採用方針）。 |

---

## 4. 設計上の重要分岐と推奨

### 4-1. 音声キャプチャ: 現状 spec の SCStream（単一）か、Recap 流 Core Audio Taps か

**推奨: システム音声は Core Audio Taps（ProcessTap）に切り替える。spec の D-1/D-9（単一 SCStream）を改訂する。**

- 理由: (1) 調査の OSS 16 件中、システム音声の実用実装は AudioCap/Recap/AudioTee/Hyprnote すべて Core Audio Taps に収斂。SCStream 音声は Voice Processing IO の罠（Scripta 記事が警告）やアプリ単位タップの粒度で不利。(2) Recap 抽出が**そのまま動くレベルの copy**を提供しており移植コストが最小。(3) **会議自動検出には別途 `SCShareableContent`（entitlement 不要）を使う**ので、「SCStream を捨てても ScreenCaptureKit は使う」ことになり矛盾しない。
- 代償: `com.apple.developer.audio-tracks-output-tap` entitlement が必要。**Recap の .entitlements にこのキーは無く、開発 provisioning profile 前提**＝ sokki の NFR-5「コード署名なし配布」と**正面衝突する重要リスク**。マイク録音（現状）は署名なしで動くが、システム音声タップは署名/profile が要る可能性が高い。→ **配布形態（個人 Developer ID 署名 or App Store）を Phase 2 前に意思決定する必要あり**（Open Question 化を推奨）。
- Phase 1 はマイクのみで変更不要（D-9 の AVAudioEngine 先行は妥当、維持）。

### 4-2. Core Data vs SwiftData

**推奨: SwiftData を維持（spec どおり）。Recap の Core Data 実装は“設計の参照”に留め、移植マッピング表に従って読み替える。**

- 理由: sokki は既に `@Model`＋`@ModelActor`＋`PersistentIdentifier` 越境で **Swift 6 strict concurrency 下の正しい形**を実装済み。Recap 抽出自身が「SwiftData の方が大幅にシンプル（performBackgroundTask 不要・同期 fetch）」と認めている。今 Core Data に戻すのは退行。
- 注意（Recap 移植時に踏む）: SwiftData は **batch delete 無し（ループ delete）**、`@Model` は非 Sendable（DTO/PersistentIdentifier で越境、既対応）、`@MainActor` の `Task{}` は `Task{ @MainActor in }` 明示。

### 4-3. 要約

**不採用（確定）。** Recap/調査の全サブシステムが「要約は完全疎結合・省略しても成立」を実証。`OpenAICompatClient.summarize()` は残置するが既定では呼ばない（BYO-API のおまけ機能）。`RecordingProcessingState` を導入する場合は summarizing(4)/summarizationFailed(7) を欠番に。

### 4-4. 翻訳の API 採用方針

**推奨: 二段構え。既定は Apple Translation Framework（オンデバイス・無料・19言語）、上級者向けに BYO-API（Gemini Live Translate / DeepL）をオプション。**

- 理由: sokki の三本柱は「ローカル完結」。リアルタイム翻訳を**初期既定でクラウド必須にすると差別化（プライバシー）が崩れる**。Apple Translation は思想一致・コスト 0・ネットワーク不要で、日本/英/中/韓を含むので会議の主要ペアは賄える。
- SuperIntern の「50言語超」を真に追うなら Gemini Live Translate（70言語）だが、**プレビュー段階・≈$2.2/時**。docs の BYO-API-Key 方針は妥当だが、**「SuperIntern が Google を使っている」は未確証（確率60-70%の推定）**なので、その前提で実装を確定させないこと。
- 既存資産活用: sokki の 16k mono Float32 は Gemini(16k Int16)とサンプルレート一致 → 変換は Float32→Int16 のみ（docs の指摘どおり）。

### 4-5. 話者分離エンジン

**推奨: Phase 3 の声紋永続化は FluidAudio を主候補に据える（SpeakerKit から差し替え）。`DiarizationEngine` protocol（D-5）が効く。**

- 理由: sokki の差別化の心臓＝embedding 永続化。**SpeakerKit v1.0 は embedding 取り出し API が未確認**（コードのコメントも「直接公開しない」）。FluidAudio は `extractEmbedding()` が public・256次元 L2 正規化済みで **SpeakerProfileStore とそのまま噛み合う**。日本語 DER も Sortformer 12.7% と Pyannote 28.8% より大幅に良い。
- ただし要確認（§5 の不足）: FluidAudio の WhisperKit セグメントとの時間軸マージは自前 ~30 行が必要。実機 DER は未測定（Open Question 維持）。

---

## 5. 「現在のコードを完全に書き換えられるレベルか」への明確な回答

### 結論: 今回の資料だけでは“フルスクラッチ再構築”はできない。増分実装を推奨。

**できる部分（資料が copy レベルで揃っており、ほぼ書き起こせる）**
- システム音声キャプチャ（ProcessTap）: Aggregate Device 辞書のキー・UUID の罠・IOProc のゼロコピー書き込み・dBFS 正規化まで Recap 抽出が具体的。WWDC24 公式サンプルが法的バックアップ。
- デュアル録音の起動/停止順序・ファイル命名規約。
- 会議自動検出サブシステム（ポーリング・bundleID・パターン）丸ごと。
- 録音後バッチ処理オーケストレーション（AsyncStream 直列キュー・スリープ復帰・キャンセル）。
- Core Data→SwiftData マッピング、要約の安全な切除。

**まだ足りない部分（資料の外にあり、実機検証 or 公式 API 確認が必須）**
1. **WhisperKit v1.0 の真のストリーミング API**: Recap は実はバッチ運用で「segment タイムスタンプ/話者を捨てている」。リアルタイム確定/仮テキストの実シグネチャは Recap 抽出に無く、sokki の擬似窓実装も暫定。→ WhisperAX の実コード確認 or 実機実験が要る。
2. **話者 embedding の取り出し（差別化の根幹）**: SpeakerKit v1.0 の embedding 公開可否が未確認。FluidAudio へ寄せる判断と、WhisperKit セグメントとのマージ実装は未存在。
3. **翻訳方式の実証**: SuperIntern の MT は推定、Gemini Live はプレビュー、Apple Translation は言語数制約。どれも「PoC で 1 本通す」までやらないと確定できない。
4. **配布 × entitlement の矛盾**: audio-tracks-output-tap が署名なし配布（NFR-5）と両立するかは未検証。これは技術というより**プロダクト意思決定の欠落**。
5. **音声ファイル I/O の不在**: 現コードは録音音声を保存していない（grep 0 件）。再生（spec の AudioPlaybackController も未作成）・バッチ再処理・Recap 流ファイルパイプラインの前提が丸ごと欠けている。
6. **実機の数値（日本語 DER・声紋閾値 0.82 の妥当性・ANE 負荷）** は全て Open Question のまま。

### 増分実装 vs 全面書き換え — 推奨と理由

**増分実装を強く推奨。**

- (1) **既存の抽象が“正解”に近い**: `TranscriptionEngine`/`DiarizationEngine` protocol、actor 分離、`@ModelActor`＋PersistentIdentifier 越境、手製 DI は Recap/調査の知見と方向が一致しており、捨てると同等品質をゼロから作り直す無駄が発生する。Recap も「`@Observable` 化は `@Published` 削除で済む」程度の差で、構造は流用前提。
- (2) **書き換えはリスクだけ高い**: 動いている「mic→WhisperKit→SwiftData→Export」経路（テスト 20 件・ExportTests/EmbeddingMatcherTests 緑）を捨てる理由が無い。
- (3) **不足項目（§5 の 1〜6）は“書き換えても解決しない”**: これらは外部 API 検証・実機計測・配布判断であり、土台を作り直しても同じ宿題が残る。
- (4) 例外: §4-1 のとおり **音声キャプチャの system レーンだけは「差し替え」**（SCStream 想定→ProcessTap）になるが、`AudioCaptureManager` という境界の内側で閉じるので**全面書き換えにはならない**。

---

## 6. 推奨ロードマップ（既存 spec の Phase と整合）

各 Phase に「spec との差分」を明記。spec §8 の Phase 構成は維持し、判断の上書きのみ加える。

### Phase 1 仕上げ（残: Issue #2〜#5）— 1 週
- #4 **音声ファイル保存（最優先・現状ゼロ）**: `AudioCaptureManager` に AVAudioFile writer を追加し、mic を `.m4a/.wav` 保存。`audioFilePath` を実体化。
- #3 durationSeconds: stop 時に `SessionManager.updateDuration` を呼ぶ（API は既存、呼び出しが無いだけ）。
- #2 E2E、#5 Markdown 確認、エクスポートにファイル保存ダイアログ＋Security-Scoped Bookmark を追加。
- 並行: Issue #22 デザイン（既に最優先指定）。

### Phase 2 — システム音声＋リアルタイム — 2〜3 週（**spec D-1/D-9 を改訂**）
- **D-1 改訂**: system レーンを ProcessTap（Core Audio Taps）で実装（Recap/WWDC24 流用）。`AudioCaptureManager` の throw を解除、`systemStream`/`systemLevelStream` 配線、`.both` のストリームマージ（Recap `AudioRecordingCoordinator` の順序）。
- **配布意思決定（ブロッカー解消）**: audio-tracks-output-tap entitlement と署名方針を確定（NFR-5 と整合させる）。
- リアルタイム文字起こし: WhisperKit v1.0 の streaming API を実機確認し、擬似窓実装を置換 or 確定境界を実装。
- 波形/レベルメーター（View は実装済み、供給を繋ぐ）。
- 会議自動検出（Recap サブシステム移植・要約非依存で安全に追加可能、Phase 2 に前倒し候補）。
- 録音後バッチ処理を `ProcessingCoordinator`（AsyncStream 直列キュー）として整理。

### Phase 3 — 話者分離＋声紋永続化（差別化の本丸）— 3〜4 週（**spec エンジン選定を補強**）
- **D-5 を活かしエンジン評価**: SpeakerKit と FluidAudio を同 protocol で比較。**embedding 取り出し＝必須要件**で、現状 FluidAudio が有力。
- `SpeakerKitEngine`/新 `FluidAudioEngine` で `DiarizationSegment.embedding` を実データ化（現 nil を解消）→ `SpeakerProfileStore` がようやく実働。
- WhisperKit セグメントと diarization のマージ（WhisperX 参照、~30 行）。
- `SpeakerProfileView` の名前編集・色・出現回数、SessionDetail の話者カラーバー。
- 実機で日本語 DER・閾値 0.82 を計測（Open Question を 1 つ閉じる）。

### Phase 4 — エクスポート拡充・音声再生・エンジン追加 — 1〜2 週
- SRT/VTT は**完了済み**（前倒し済）。残: ファイル出力 UI。
- `AudioPlaybackController` 新規作成（spec に名前だけ）→ セグメントクリック再生（FR-DATA-3、Phase 2 のファイル保存が前提）。
- ファイルインポート（.mp4/.m4a/.wav/.mp3、`AudioFileImporter` も spec のみで未作成）。
- macOS 26 で Apple SpeechAnalyzer/SpeechTranscriber（swift-scribe 参照）を protocol ドロップイン評価。

### Phase 5 — 翻訳・LLM・配布 — 2〜3 週（**docs/superintern-feature-plan を統合・方針上書き**）
- **翻訳（既定 = Apple Translation オンデバイス、上級 = BYO-API Gemini/DeepL）**。superintern-plan の「Gemini 既定」は §4-4 のとおりオプション扱いに格下げ推奨。
- LLM: `OpenAICompatClient` を配線（話者名推定・任意サマリー）。API キーは Keychain（Recap `KeychainService` 参照）へ移し、AppSettings 平文を解消。
- Homebrew Cask 配布 ＋ Gatekeeper 回避ドキュメント（NFR-5、Phase 2 の署名判断と一体）。

---

### 付記（参照ファイルの絶対パス）
- 実コード: `/Users/yosuke/workspace/github.com/YosukeIida/sokki/Sources/SokkiKit/**`（特に `Audio/AudioCaptureManager.swift`, `Transcription/WhisperKitEngine.swift`・`TranscriptionPipeline.swift`, `Diarization/SpeakerKitEngine.swift`, `SpeakerProfile/SpeakerProfileStore.swift`）
- 仕様: `/Users/yosuke/workspace/github.com/YosukeIida/sokki/spec.md`, `/.../requirements.md`
- 既存プラン: `/Users/yosuke/workspace/github.com/YosukeIida/sokki/docs/superintern-feature-plan.md`
- 検証コマンド: `grep -rn "AVAudioFile|SCStream|CATapDescription|extractEmbedding|Translation" Sources/` → 音声ファイル I/O・システムタップ・翻訳・embedding 取り出しは **0 件**（未実装を事実確認）。
