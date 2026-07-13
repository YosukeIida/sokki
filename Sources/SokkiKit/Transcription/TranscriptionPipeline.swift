import Foundation
import SwiftData
import os

struct TranscriptSegmentViewModel: Identifiable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    var speakerName: String?

    init(_ segment: any TranscriptionSegment, speakerName: String? = nil) {
        self.id = UUID()
        self.start = segment.start
        self.end = segment.end
        self.text = segment.text
        self.speakerName = speakerName
    }
}

@Observable
@MainActor
final class TranscriptionPipeline {

    private(set) var confirmedSegments: [TranscriptSegmentViewModel] = []
    private(set) var hypothesisText: String = ""
    private(set) var isRunning: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var loadingMessage: String = ""
    /// モデルダウンロードの進捗（0...1）。ダウンロード段階以外や進捗が取得できない場合は nil。
    private(set) var downloadProgress: Double? = nil
    private(set) var elapsedSeconds: Double = 0
    /// 録音ファイルの保存に問題が発生した場合の利用者向けメッセージ（P1）。
    private(set) var recordingSaveErrorMessage: String? = nil
    /// 文字起こしの最終処理でエラーが起きた際の非致命的な通知メッセージ（P2）。
    private(set) var transcriptionNoticeMessage: String? = nil

    /// マイク／システムの実レベル（dBFS RMS、-60...0）。WaveformView / LevelMeterView へ供給する（TASK-13）。
    /// `captureManager` は `start` のたびにストリームを作り直す（AsyncStream は使い捨て）ため、
    /// `start()` 完了時に最新のストリームへ差し替える。
    private(set) var micLevelStream: AsyncStream<Float> = AsyncStream { $0.finish() }
    private(set) var systemLevelStream: AsyncStream<Float> = AsyncStream { $0.finish() }

    private let captureManager: AudioCaptureManager
    private let transcriptionEngine: any TranscriptionEngine
    private let diarizationEngine: any DiarizationEngine
    private let speakerStore: SpeakerProfileStore
    private let sessionManager: SessionManager

    private var captureTask: Task<Void, Error>?
    private var timerTask: Task<Void, Never>?
    private var currentSessionID: PersistentIdentifier?
    private var recordingStartedAt: Date?
    /// stop() の停止後処理（フラッシュ・保存・diarization）実行中フラグ。
    /// この間は start()/stop() の再入を拒否し、後処理対象のセッション状態が差し替わるのを防ぐ。
    private var isFinalizing = false

    private let logger = Logger(subsystem: "com.sokki.app", category: "diarization")

    /// 録音停止後の後処理（最終 flush → 保存）を直列に流すオーケストレータ（TASK-16 / P2-6）。
    /// AppDependencyContainer の組み立て時に `attach(coordinator:)` で注入する。未注入（Preview / 一部テスト）
    /// の場合は後処理をインラインで実行してフォールバックする。
    private(set) var coordinator: ProcessingCoordinator?
    /// 停止操作時に確定した録音長。後処理ジョブ（finalizeTranscription）が保存に使う。
    private var pendingDuration: TimeInterval?
    /// stop() の再入ガード。停止処理は複数の await を跨ぐため、二重呼び出しで同一セッションの
    /// ジョブが二重 enqueue され、共有状態（pendingDuration）が上書きされるのを防ぐ。
    private var isStopping = false

    init(
        captureManager: AudioCaptureManager,
        transcriptionEngine: any TranscriptionEngine,
        diarizationEngine: any DiarizationEngine,
        speakerStore: SpeakerProfileStore,
        sessionManager: SessionManager
    ) {
        self.captureManager = captureManager
        self.transcriptionEngine = transcriptionEngine
        self.diarizationEngine = diarizationEngine
        self.speakerStore = speakerStore
        self.sessionManager = sessionManager
    }

    func start(
        mode: AudioCaptureManager.CaptureMode,
        sessionTitle: String,
        transcriptionLanguage: String? = nil
    ) async throws {
        // 前回録音の停止後処理（isFinalizing）中の開始は拒否する。許可すると stop() 側の
        // await をまたいで currentSessionID / captureTask が差し替わり、旧セッションの
        // duration 保存・diarization が新セッションへ誤適用され得る。
        guard !isRunning, !isFinalizing else { return }

        await transcriptionEngine.setTranscriptionLanguage(transcriptionLanguage)

        if await !transcriptionEngine.isReady {
            isLoading = true
            loadingMessage = "WhisperKit モデルをダウンロード中…\n初回は数分かかります"
            downloadProgress = 0
            defer { isLoading = false; loadingMessage = ""; downloadProgress = nil }
            try await transcriptionEngine.prepare(onProgress: { [weak self] phase in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch phase {
                    case .downloading(let fractionCompleted):
                        self.downloadProgress = fractionCompleted
                        self.loadingMessage = "WhisperKit モデルをダウンロード中…"
                    case .loadingIntoMemory:
                        self.downloadProgress = nil
                        self.loadingMessage = "モデルを読み込み中…"
                    }
                }
            })
        }

        let title = sessionTitle.isEmpty
            ? "録音_\(DateFormatter.sessionTitle.string(from: .now))"
            : sessionTitle

        let sessionID = try await sessionManager.createSession(title: title, mode: mode)
        currentSessionID = sessionID
        recordingStartedAt = Date()

        // 録音ファイルの書き出し先を渡す（P1-1）
        let audioURL = await sessionManager.audioURL(forSessionID: sessionID)
        try await captureManager.startCapture(mode: mode, outputURL: audioURL)
        recordingSaveErrorMessage = await captureManager.recordingSaveError.map(makeSaveErrorMessage)

        // このセッション用に作り直された最新のレベルストリームへ差し替える（TASK-13）。
        micLevelStream = await captureManager.micLevelStream
        systemLevelStream = await captureManager.systemLevelStream

        isRunning = true
        elapsedSeconds = 0
        confirmedSegments = []
        hypothesisText = ""

        startTimer()

        captureTask = Task {
            let source: AsyncStream<AudioChunk>
            switch mode {
            case .micOnly:    source = await captureManager.micStream
            case .systemOnly: source = await captureManager.systemStream
            case .both:
                // Both モード（TASK-12）: mic / system の 2 ストリームを到着順にインターリーブして
                // 1 本化し、単一の文字起こしストリームへ供給する（MVP）。レーン分離の高度化は
                // Phase 3 のマージ（TASK-26）に委ねる。
                let mic = await captureManager.micStream
                let system = await captureManager.systemStream
                source = mergeAudioStreams(mic, system)
            }

            let transcriptStream = await transcriptionEngine.transcribeStream(audioChunks: source)

            // captureTask は @MainActor コンテキストで生成されるため MainActor 隔離を継承する。
            // よって confirmedSegments / hypothesisText への代入はそのまま MainActor 上で行える。
            for try await update in transcriptStream {
                for segment in update.newlyConfirmed {
                    confirmedSegments.append(TranscriptSegmentViewModel(segment))
                }
                hypothesisText = update.hypothesis

                // 確定セグメントは録音開始時にキャプチャした sessionID で保存する（stop() の
                // 後処理と並行してもフラッシュ分のセグメント保存が失われない）。
                for segment in update.newlyConfirmed {
                    try await sessionManager.appendSegment(segment, toSessionID: sessionID)
                }
            }
        }
    }

    /// 後処理オーケストレータを注入する（AppDependencyContainer 組み立て時に 1 回だけ呼ぶ）。
    func attach(coordinator: ProcessingCoordinator) {
        self.coordinator = coordinator
    }

    func stop() async throws {
        // 再入ガード: 停止処理中の二重呼び出しは無視する（同一セッションの二重ジョブ enqueue・
        // diarization 二重実行・pendingDuration 上書きを防ぐ）。defer で全経路で確実に戻す。
        guard isRunning, !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        // 停止後処理（フラッシュ〜diarization）が完了するまで start() を拒否する（isFinalizing）。
        // 許可すると await をまたいで currentSessionID / captureTask が差し替わり、旧セッションの
        // duration 保存・diarization が新セッションへ誤適用され得る。
        isFinalizing = true
        defer { isFinalizing = false }

        timerTask?.cancel()

        // 録音長は「開始〜停止操作まで」の実時間で確定（後続フラッシュ時間を含めない・P1-2）
        pendingDuration = recordingStartedAt.map { Date().timeIntervalSince($0) }

        // 1. ストリームを閉じる（transcribeStream のフラッシュがトリガーされる）
        await captureManager.stopCapture()
        if let error = await captureManager.recordingSaveError {
            recordingSaveErrorMessage = makeSaveErrorMessage(error)
        }

        // 2. 以降の後処理（flush 待ち → フォールバック永続化 → 録音長保存）を ProcessingCoordinator の
        //    ジョブとして直列に流す。将来はこの前段に diarization ジョブが挿入される（TASK-25 統合時）。
        guard let sid = currentSessionID else {
            captureTask = nil
            isRunning = false
            recordingStartedAt = nil
            return
        }

        isLoading = true
        loadingMessage = ProcessingJobKind.finalizeTranscription.displayName
        let job = ProcessingJob(sessionID: sid, kind: .finalizeTranscription)
        if let coordinator {
            // process(_:) は「このジョブの完了」まで待つ。runner が内部でエラー/キャンセルを保存に
            // 変換するため、ここで throw されても停止処理は完了扱いとする。
            try? await coordinator.process(job)
        } else {
            // Coordinator 未注入時（Preview 等）はインラインで後処理を実行し、従来挙動を維持する。
            await runProcessingJob(job)
        }
        isLoading = false
        loadingMessage = ""

        // Phase 3: 録音全体に対して diarization をバッチ実行し、話者プロファイルを解決・付与する。
        // ここまでにセグメントは保存済みのため、diarization が失敗しても文字起こし結果は保持される。
        // （.diarize ジョブへの移行は ProcessingCoordinator 統合タスクで行う — TASK-25/TASK-16 申し送り）
        await runDiarizationIfEnabled(sessionID: sid)

        captureTask = nil
        isRunning = false
        recordingStartedAt = nil
    }

    /// ProcessingCoordinator から呼ばれる後処理ジョブのディスパッチ。ジョブ種別ごとに処理を振り分ける。
    /// 自身でエラー/キャンセルを保存に変換し、原則 throw しない（1 件の失敗が後続を止めないため）。
    func runProcessingJob(_ job: ProcessingJob) async {
        switch job.kind {
        case .finalizeTranscription:
            await finalizeTranscription(sessionID: job.sessionID)
        case .diarize:
            // 将来のフック（TASK-25 統合時にここでバッチ話者分離を呼ぶ）。本ブランチでは未実装。
            break
        }
    }

    /// 録音停止後の文字起こし仕上げ。フラッシュ完了を待ち、失敗・キャンセル時は画面上の未確定テキストを
    /// フォールバック保存する。最後に録音長を確定する。
    private func finalizeTranscription(sessionID: PersistentIdentifier) async {
        do {
            // フラッシュ（バッファ内の残音声を文字起こし）が終わるまで待つ。
            try await captureTask?.value
        } catch is CancellationError {
            // ジョブ/アプリ終了によるキャンセル時も、画面に残る未確定テキストを保存して
            // 部分結果を残す（TASK-16 AC3）。確定セグメントはストリーミング中に永続化済み。
            await persistPendingHypothesisFallback()
        } catch {
            // 文字起こしの最終 flush が失敗しても、画面に出ている未確定テキストを
            // フォールバックとして確定・保存し、未確定分の消失を防ぐ（MAJOR-2b）。
            // エラー自体はログ + 非致命的な UI 通知にとどめ、セッションは保存する。
            await persistPendingHypothesisFallback()
            transcriptionNoticeMessage = "文字起こしの最終処理でエラーが発生しました。認識済みのテキストは保存されています。"
            NSLog("TranscriptionPipeline: final transcription flush failed: \(error.localizedDescription)")
        }

        // 録音長を保存（P1-2）。失敗してもセッション自体は保持する。
        if let duration = pendingDuration {
            try? await sessionManager.updateDuration(sessionID: sessionID, duration: duration)
        }
        pendingDuration = nil
    }

    // MARK: - Diarization（P3）

    /// 設定が有効なら、保存済み音声ファイルを読み込み diarization → 話者プロファイル付与を行う。
    /// 音声が読めない・設定が無効などの場合は何もしない（graceful degradation）。
    private func runDiarizationIfEnabled(sessionID: PersistentIdentifier) async {
        guard await sessionManager.diarizationEnabled() else { return }
        guard let audioURL = await sessionManager.audioURL(forSessionID: sessionID),
              FileManager.default.fileExists(atPath: audioURL.path) else {
            logger.notice("話者分離をスキップ: 録音ファイルが見つかりません")
            return
        }
        let samples: [Float]
        do {
            samples = try AudioFileReader.readMonoSamples(url: audioURL)
        } catch {
            logger.error("話者分離をスキップ: 音声の読み込みに失敗しました: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !samples.isEmpty else { return }

        // diarization（初回はモデル DL を伴い時間がかかる）中は UI に進捗を示す。
        isLoading = true
        loadingMessage = "話者を識別中…"
        defer {
            isLoading = false
            loadingMessage = ""
        }
        await diarizeAndAssign(audioSamples: samples, sessionID: sessionID)
    }

    /// diarization → プロファイル解決 → セグメント付与を実行する（非スロー）。
    /// 失敗はログに残すのみで、文字起こし結果の保存を妨げない（graceful degradation）。
    /// テストから直接呼べるよう internal 可視性。
    func diarizeAndAssign(audioSamples: [Float], sessionID: PersistentIdentifier) async {
        do {
            try await applyDiarization(audioSamples: audioSamples, sessionID: sessionID)
        } catch {
            logger.error("話者分離に失敗しました（非致命）: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// diarization の中核処理（スロー）。テストから直接呼べるよう internal 可視性。
    func applyDiarization(audioSamples: [Float], sessionID: PersistentIdentifier) async throws {
        if await !diarizationEngine.isReady {
            try await diarizationEngine.prepare()
        }
        let result = try await diarizationEngine.diarize(audioArray: audioSamples)

        // 設定の声紋照合閾値をここで反映する（照合の直前・TASK-27）。
        // AppSettingsModel.embeddingMatchThreshold は以前から存在したが未配線だった。
        let threshold = await sessionManager.embeddingMatchThreshold()
        await speakerStore.updateThreshold(threshold)

#if DEBUG
        // 今回の録音1回分の diarization クラスタリング安定性の診断（TASK-27）。UI には出さず、
        // DEBUG ビルドでのみ Logger（category "diagnostics"）へ INFO 出力する。
        // NOTE: 録音間の実際の照合閾値の妥当性は、この下の resolveProfiles 内部で出力される
        // `[TASK-27 実照合]` ログ（SpeakerProfileStore）の方を参照すること（レビュー指摘対応）。
        EmbeddingSimilarityReport.compute(from: result).log()
#endif

        let mapping = try await speakerStore.resolveProfiles(from: result)
        try await sessionManager.assignSpeakersByOverlap(
            sessionID: sessionID,
            diarizationSegments: result.segments,
            profileMapping: mapping
        )
    }

    /// 利用者がエラーバナーを閉じたときに呼ぶ。
    func dismissRecordingSaveError() {
        recordingSaveErrorMessage = nil
    }

    /// 利用者が文字起こし通知バナーを閉じたときに呼ぶ。
    func dismissTranscriptionNotice() {
        transcriptionNoticeMessage = nil
    }

    /// 最終 flush が失敗した場合のフォールバック。画面に残っている未確定テキスト（hypothesis）を
    /// 確定セグメントとして保存し、UI にも反映する。タイムスタンプは最善努力（直近の確定終端〜経過秒）。
    private func persistPendingHypothesisFallback() async {
        let text = hypothesisText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let start = confirmedSegments.last?.end ?? 0
        let end = max(start, elapsedSeconds)
        let segment = TranscriptionSegmentSnapshot(
            start: start,
            end: end,
            text: text,
            isConfirmed: true,
            avgLogProb: 0
        )
        confirmedSegments.append(TranscriptSegmentViewModel(segment))
        hypothesisText = ""

        if let sid = currentSessionID {
            try? await sessionManager.appendSegment(segment, toSessionID: sid)
        }
    }

#if DEBUG
    /// テスト専用: start() を経ずに stop() の後処理フロー（フラッシュ・保存・diarization）を
    /// 駆動できるよう内部状態を注入する。
    func primeForStopTesting(sessionID: PersistentIdentifier) {
        isRunning = true
        currentSessionID = sessionID
        recordingStartedAt = Date()
    }

    func setForPreview(
        isRunning: Bool = false,
        isLoading: Bool = false,
        loadingMessage: String = "",
        downloadProgress: Double? = nil,
        elapsedSeconds: Double = 0,
        confirmedSegments: [TranscriptSegmentViewModel] = [],
        hypothesisText: String = ""
    ) {
        self.isRunning = isRunning
        self.isLoading = isLoading
        self.loadingMessage = loadingMessage
        self.downloadProgress = downloadProgress
        self.elapsedSeconds = elapsedSeconds
        self.confirmedSegments = confirmedSegments
        self.hypothesisText = hypothesisText
    }
#endif

    private func makeSaveErrorMessage(_ error: Error) -> String {
        "録音ファイルの保存に失敗しました。ディスクの空き容量を確認してください。（\(error.localizedDescription)）"
    }

    private func startTimer() {
        let start = Date()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds = Date().timeIntervalSince(start)
            }
        }
    }
}

private extension DateFormatter {
    static let sessionTitle: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f
    }()
}
