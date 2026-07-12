import SwiftUI
import SwiftData

@Observable
@MainActor
public final class AppDependencyContainer {
    let captureManager: AudioCaptureManager
    let transcriptionEngine: WhisperKitEngine
    let diarizationEngine: SpeakerKitEngine
    let speakerProfileStore: SpeakerProfileStore
    let sessionManager: SessionManager
    var pipeline: TranscriptionPipeline
    let coordinator: ProcessingCoordinator

    public init(modelContainer: ModelContainer) {
        let ctx = ModelContext(modelContainer)

        captureManager = AudioCaptureManager()
        transcriptionEngine = WhisperKitEngine()
        diarizationEngine = SpeakerKitEngine()
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

        // 後処理オーケストレータ。runner は Pipeline のジョブディスパッチに委譲する。
        coordinator = ProcessingCoordinator(runner: { [weak pipeline] job in
            await pipeline?.runProcessingJob(job)
        })
        pipeline.attach(coordinator: coordinator)
    }
}
