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

    // Phase 2 で実装（SCStream 連携後に有効化）
    // var micLevelStream:    AsyncStream<Float> { ... }
    // var systemLevelStream: AsyncStream<Float> { ... }

    private let captureManager: AudioCaptureManager
    private let transcriptionEngine: any TranscriptionEngine
    private let diarizationEngine: any DiarizationEngine
    private let speakerStore: SpeakerProfileStore
    private let sessionManager: SessionManager

    private var captureTask: Task<Void, Error>?
    private var timerTask: Task<Void, Never>?
    private var currentSessionID: PersistentIdentifier?
    private var recordingStartedAt: Date?

    private let logger = Logger(subsystem: "com.sokki.app", category: "diarization")

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

    func start(mode: AudioCaptureManager.CaptureMode, sessionTitle: String) async throws {
        guard !isRunning else { return }

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
            case .both:       source = await captureManager.micStream  // TODO: Phase 2 でストリームマージ
            }

            let transcriptStream = await transcriptionEngine.transcribeStream(audioChunks: source)

            for try await segment in transcriptStream {
                await MainActor.run {
                    if segment.isConfirmed {
                        confirmedSegments.append(TranscriptSegmentViewModel(segment))
                        hypothesisText = ""
                    } else {
                        hypothesisText = segment.text
                    }
                }
                if segment.isConfirmed, let sid = currentSessionID {
                    try await sessionManager.appendSegment(segment, toSessionID: sid)
                }
            }
        }
    }

    func stop() async throws {
        // 再入ガード: stop() が二度呼ばれても同一セッションへ diarization を二重実行しない
        // （SpeakerProfileModel.embeddingCount の二重加算を防ぐ）。isRunning を即座に倒すことで、
        // 後続のフラッシュ待ち中に再入した stop() も早期 return する。
        guard isRunning else { return }
        isRunning = false

        timerTask?.cancel()

        // 録音長は「開始〜停止操作まで」の実時間で確定（後続フラッシュ時間を含めない・P1-2）
        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) }

        // 1. ストリームを閉じる（transcribeStream のフラッシュがトリガーされる）
        await captureManager.stopCapture()
        if let error = await captureManager.recordingSaveError {
            recordingSaveErrorMessage = makeSaveErrorMessage(error)
        }

        // 2. フラッシュ（バッファ内の残音声を文字起こし）が終わるまで待つ
        isLoading = true
        loadingMessage = "文字起こし処理中…"
        do {
            try await captureTask?.value
        } catch is CancellationError {
            // ユーザーが強制中断した場合は無視
        } catch {
            // 文字起こしエラーは無視してセッションを保存
        }
        isLoading = false
        loadingMessage = ""
        captureTask = nil

        // 録音長を保存（P1-2）。失敗してもセッション自体は保持する。
        if let sid = currentSessionID, let duration {
            try? await sessionManager.updateDuration(sessionID: sid, duration: duration)
        }

        // Phase 3: 録音全体に対して diarization をバッチ実行し、話者プロファイルを解決・付与する。
        // ここまでにセグメントは保存済みのため、diarization が失敗しても文字起こし結果は保持される。
        if let sid = currentSessionID {
            await runDiarizationIfEnabled(sessionID: sid)
        }

        // 後処理完了。再入時に同一セッションを再処理しないよう状態をクリアする。
        currentSessionID = nil
        recordingStartedAt = nil
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
