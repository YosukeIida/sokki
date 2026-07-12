import Foundation
@preconcurrency import FluidAudio

/// The narrow actor boundary around FluidAudio's non-Sendable manager.
protocol FluidAudioManaging: Sendable {
    func prepareModels() async throws
    func process(audio: [Float]) async throws -> FluidAudio.DiarizationResult
}

/// `OfflineDiarizerManager` contains Core ML reference types. Keeping it inside this actor
/// prevents concurrent access even while `FluidAudioEngine` is suspended at an await.
private actor FluidAudioManagerAdapter: FluidAudioManaging {
    private let manager: OfflineDiarizerManager

    init() {
        manager = OfflineDiarizerManager()
    }

    func prepareModels() async throws {
        try await manager.prepareModels()
    }

    func process(audio: [Float]) async throws -> FluidAudio.DiarizationResult {
        try await manager.process(audio: audio)
    }
}

actor FluidAudioEngine: DiarizationEngine {
    /// WeSpeaker ResNet34 embedding dimension exposed by FluidAudio.
    static let embeddingDimension = 256

    private let manager: any FluidAudioManaging
    private(set) var isReady = false

    init() {
        manager = FluidAudioManagerAdapter()
    }

    init(manager: any FluidAudioManaging) {
        self.manager = manager
    }

    func prepare() async throws {
        do {
            try await manager.prepareModels()
            isReady = true
        } catch {
            isReady = false
            throw DiarizationEngineError.modelLoadFailed(underlying: error)
        }
    }

    func diarize(audioArray: [Float]) async throws -> DiarizationResult {
        guard isReady else { throw DiarizationEngineError.notPrepared }

        let result: FluidAudio.DiarizationResult
        do {
            result = try await manager.process(audio: audioArray)
        } catch {
            throw DiarizationEngineError.diarizationFailed(underlying: error)
        }

        let segments = try result.segments.map { segment in
            guard segment.embedding.count == Self.embeddingDimension else {
                throw DiarizationEngineError.invalidEmbedding(
                    expected: Self.embeddingDimension,
                    actual: segment.embedding.count
                )
            }

            return DiarizationSegment(
                start: TimeInterval(segment.startTimeSeconds),
                end: TimeInterval(segment.endTimeSeconds),
                speakerID: segment.speakerId,
                embedding: l2Normalize(segment.embedding)
            )
        }

        return DiarizationResult(
            segments: segments,
            numberOfSpeakers: Set(segments.map(\.speakerID)).count
        )
    }
}
