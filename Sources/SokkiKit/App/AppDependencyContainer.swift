import SwiftUI
import SwiftData

@Observable
@MainActor
public final class AppDependencyContainer {
    let captureManager: AudioCaptureManager
    let transcriptionEngine: WhisperKitEngine
    let diarizationEngine: any DiarizationEngine
    let speakerProfileStore: SpeakerProfileStore
    let sessionManager: SessionManager
    var pipeline: TranscriptionPipeline
    let importer: AudioFileImporter

    public init(modelContainer: ModelContainer) {
        let ctx = ModelContext(modelContainer)

        captureManager = AudioCaptureManager()
        transcriptionEngine = WhisperKitEngine()
        diarizationEngine = FluidAudioEngine()
        speakerProfileStore = SpeakerProfileStore(modelContext: ctx)
        sessionManager = SessionManager(modelContainer: modelContainer)

        let pipeline = TranscriptionPipeline(
            captureManager: captureManager,
            transcriptionEngine: transcriptionEngine,
            diarizationEngine: diarizationEngine,
            speakerStore: speakerProfileStore,
            sessionManager: sessionManager
        )
        self.pipeline = pipeline

        importer = AudioFileImporter(
            transcriptionEngine: transcriptionEngine,
            sessionManager: sessionManager,
            pipeline: pipeline
        )
    }
}
