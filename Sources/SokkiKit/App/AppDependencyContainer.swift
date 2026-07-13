import SwiftUI
import SwiftData

@Observable
@MainActor
public final class AppDependencyContainer {
    let modelContainer: ModelContainer
    let captureManager: AudioCaptureManager
    let transcriptionEngine: WhisperKitEngine
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
        transcriptionEngine = WhisperKitEngine()
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
}
