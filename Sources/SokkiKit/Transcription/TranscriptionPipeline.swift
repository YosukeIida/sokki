import Foundation
import SwiftData

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

                // 確定セグメントのみを永続化する（既存フロー維持）。
                if let sid = currentSessionID {
                    for segment in update.newlyConfirmed {
                        try await sessionManager.appendSegment(segment, toSessionID: sid)
                    }
                }
            }
        }
    }

    func stop() async throws {
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
            // 文字起こしの最終 flush が失敗しても、画面に出ている未確定テキストを
            // フォールバックとして確定・保存し、未確定分の消失を防ぐ（MAJOR-2b）。
            // エラー自体はログ + 非致命的な UI 通知にとどめ、セッションは保存する。
            await persistPendingHypothesisFallback()
            transcriptionNoticeMessage = "文字起こしの最終処理でエラーが発生しました。認識済みのテキストは保存されています。"
            NSLog("TranscriptionPipeline: final transcription flush failed: \(error.localizedDescription)")
        }
        isLoading = false
        loadingMessage = ""
        captureTask = nil

        isRunning = false

        // 録音長を保存（P1-2）。失敗してもセッション自体は保持する。
        if let sid = currentSessionID, let duration {
            try? await sessionManager.updateDuration(sessionID: sid, duration: duration)
        }
        recordingStartedAt = nil
        // Phase 3 で: diarization をバッチ実行
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
