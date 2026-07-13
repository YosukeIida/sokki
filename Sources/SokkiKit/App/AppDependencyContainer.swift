import SwiftUI
import SwiftData

@Observable
@MainActor
public final class AppDependencyContainer {
    let modelContainer: ModelContainer
    let captureManager: AudioCaptureManager
    let transcriptionEngine: any TranscriptionEngine
    let diarizationEngine: SpeakerKitEngine
    let speakerProfileStore: SpeakerProfileStore
    let sessionManager: SessionManager
    var pipeline: TranscriptionPipeline
    /// 会議自動検出（TASK-15）。`start()` を呼ぶまで SCShareableContent には触れない。
    let meetingDetector: MeetingDetector

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let ctx = ModelContext(modelContainer)

        captureManager = AudioCaptureManager()
        let engineChoice = (try? ctx.fetch(FetchDescriptor<AppSettingsModel>()))?
            .first?.transcriptionEngine ?? "whisperkit"
        transcriptionEngine = Self.makeTranscriptionEngine(engineChoice: engineChoice)
        diarizationEngine = SpeakerKitEngine()
        speakerProfileStore = SpeakerProfileStore(modelContext: ctx)
        sessionManager = SessionManager(modelContainer: modelContainer)
        meetingDetector = MeetingDetector()

        pipeline = TranscriptionPipeline(
            captureManager: captureManager,
            transcriptionEngine: transcriptionEngine,
            diarizationEngine: diarizationEngine,
            speakerStore: speakerProfileStore,
            sessionManager: sessionManager
        )
    }

    /// エンジン選択値から `TranscriptionEngine` を生成する。
    /// `"speechAnalyzer"` は macOS 26 以降でのみ選択可能。未対応環境では常に WhisperKit へフォールバックする。
    static func makeTranscriptionEngine(engineChoice: String) -> any TranscriptionEngine {
        if engineChoice == "speechAnalyzer" {
            if #available(macOS 26.0, *) {
                return SpeechAnalyzerEngine()
            }
        }
        return WhisperKitEngine()
    }
}
