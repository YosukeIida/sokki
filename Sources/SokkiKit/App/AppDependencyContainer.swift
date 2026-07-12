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

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let ctx = ModelContext(modelContainer)

        captureManager = AudioCaptureManager()
        transcriptionEngine = WhisperKitEngine()
        diarizationEngine = SpeakerKitEngine()
        speakerProfileStore = SpeakerProfileStore(modelContext: ctx)
        sessionManager = SessionManager(modelContainer: modelContainer)

        pipeline = TranscriptionPipeline(
            captureManager: captureManager,
            transcriptionEngine: transcriptionEngine,
            diarizationEngine: diarizationEngine,
            speakerStore: speakerProfileStore,
            sessionManager: sessionManager
        )
    }
}
