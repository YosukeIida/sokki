#if DEBUG
import SwiftData
import SwiftUI

// MARK: - Preview 用 Pipeline 状態注入ヘルパー

/// Xcode Preview で各状態の RecordingView を確認するためのヘルパー
@MainActor
enum PreviewPipeline {

    /// アイドル状態（起動直後）
    static func idle() -> TranscriptionPipeline {
        makePipeline()
    }

    /// ローディング状態（モデルDL中・進捗あり）
    static func loading() -> TranscriptionPipeline {
        let p = makePipeline()
        p.setForPreview(
            isLoading: true,
            loadingMessage: "WhisperKit モデルをダウンロード中…",
            downloadProgress: 0.42
        )
        return p
    }

    /// ローディング状態（メモリへのロード中・進捗率なし）
    static func loadingIntoMemory() -> TranscriptionPipeline {
        let p = makePipeline()
        p.setForPreview(isLoading: true, loadingMessage: "モデルを読み込み中…")
        return p
    }

    /// 録音中（セグメントなし）
    static func recording() -> TranscriptionPipeline {
        let p = makePipeline()
        p.setForPreview(isRunning: true, elapsedSeconds: 42)
        return p
    }

    /// 録音中（テキスト流入）
    static func recordingWithText() -> TranscriptionPipeline {
        let p = makePipeline()
        let segs: [TranscriptSegmentViewModel] = [
            .init(text: "本日はお集まりいただきありがとうございます。", start: 0, end: 3),
            .init(text: "今日のアジェンダを共有します。", start: 3, end: 6),
            .init(text: "まず進捗報告から始めましょう。", start: 6, end: 9),
        ]
        p.setForPreview(isRunning: true, elapsedSeconds: 65, confirmedSegments: segs, hypothesisText: "次に…")
        return p
    }

    // MARK: Private

    private static func makePipeline() -> TranscriptionPipeline {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: SessionModel.self, SegmentModel.self, SpeakerProfileModel.self, AppSettingsModel.self,
            configurations: config
        )
        return TranscriptionPipeline(
            captureManager: AudioCaptureManager(),
            transcriptionEngine: PreviewTranscriptionEngine(),
            diarizationEngine: PreviewDiarizationEngine(),
            speakerStore: SpeakerProfileStore(modelContext: ModelContext(container)),
            sessionManager: SessionManager(modelContainer: container)
        )
    }
}

/// Preview 専用: 即座に完了するダミー文字起こしエンジン
private actor PreviewTranscriptionEngine: TranscriptionEngine {
    private(set) var isReady = true
    var modelIdentifier = "preview"
    func prepare(onProgress: @escaping @Sendable (TranscriptionEngineLoadPhase) -> Void) async throws {}
    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment] { [] }
    func transcribeStream(audioChunks: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptionStreamUpdate, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// Preview 専用: 即座に完了するダミー話者分離エンジン
private actor PreviewDiarizationEngine: DiarizationEngine {
    private(set) var isReady = true
    func prepare() async throws {}
    func diarize(audioArray: [Float]) async throws -> DiarizationResult {
        DiarizationResult(segments: [], numberOfSpeakers: 0)
    }
}

// MARK: - TranscriptSegmentViewModel Preview 用イニシャライザ

extension TranscriptSegmentViewModel {
    init(text: String, start: TimeInterval = 0, end: TimeInterval = 1) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.text = text
        self.speakerName = nil
    }
}

// MARK: - AppDependencyContainer Preview 用イニシャライザ

extension AppDependencyContainer {
    /// Preview 専用: 指定した pipeline を持つコンテナ
    static func preview(pipeline: TranscriptionPipeline) -> AppDependencyContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: SessionModel.self, SegmentModel.self, SpeakerProfileModel.self, AppSettingsModel.self,
            configurations: config
        )
        let deps = AppDependencyContainer(modelContainer: container)
        deps.pipeline = pipeline
        return deps
    }
}

#endif
