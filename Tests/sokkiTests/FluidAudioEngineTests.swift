import FluidAudio
import Testing
@testable import SokkiKit

@Suite("FluidAudioEngine")
struct FluidAudioEngineTests {
    @Test("DiarizationEngine protocol として交換できる")
    func conformsToProtocol() {
        let engine: any DiarizationEngine = FluidAudioEngine(manager: MockFluidAudioManager())
        _ = engine
    }

    @Test("prepare 前の diarize は notPrepared")
    func rejectsDiarizationBeforePrepare() async {
        let engine = FluidAudioEngine(manager: MockFluidAudioManager())

        do {
            _ = try await engine.diarize(audioArray: [])
            Issue.record("diarize should throw")
        } catch DiarizationEngineError.notPrepared {
            // Expected.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("モデル取得失敗を modelLoadFailed に変換する")
    func mapsModelLoadFailure() async {
        let engine = FluidAudioEngine(
            manager: MockFluidAudioManager(prepareError: StubError.unavailable)
        )

        do {
            try await engine.prepare()
            Issue.record("prepare should throw")
        } catch case DiarizationEngineError.modelLoadFailed {
            let isReady = await engine.isReady
            #expect(isReady == false)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("推論失敗を diarizationFailed に変換する")
    func mapsProcessingFailure() async throws {
        let engine = FluidAudioEngine(
            manager: MockFluidAudioManager(processError: StubError.unavailable)
        )
        try await engine.prepare()

        do {
            _ = try await engine.diarize(audioArray: [0])
            Issue.record("diarize should throw")
        } catch case DiarizationEngineError.diarizationFailed {
            // Expected.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("FluidAudio の 256 次元 embedding を L2 正規化して返す")
    func mapsNormalizedEmbedding() async throws {
        let rawEmbedding = (1...FluidAudioEngine.embeddingDimension).map(Float.init)
        let upstream = [
            TimedSpeakerSegment(
                speakerId: "S1",
                embedding: rawEmbedding,
                startTimeSeconds: 1.25,
                endTimeSeconds: 3.5,
                qualityScore: 0.9
            )
        ]
        let engine = FluidAudioEngine(manager: MockFluidAudioManager(result: upstream))

        try await engine.prepare()
        let result = try await engine.diarize(audioArray: [0])

        #expect(result.numberOfSpeakers == 1)
        #expect(result.segments.count == 1)
        #expect(result.segments[0].speakerID == "S1")
        #expect(result.segments[0].start == 1.25)
        #expect(result.segments[0].end == 3.5)
        let embedding = try #require(result.segments[0].embedding)
        #expect(embedding.count == FluidAudioEngine.embeddingDimension)
        let norm = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        #expect(abs(norm - 1) < 1e-5)
    }

    @Test("embedding 次元の不一致を明示的に拒否する")
    func rejectsUnexpectedEmbeddingDimension() async throws {
        let upstream = [
            TimedSpeakerSegment(
                speakerId: "S1",
                embedding: [1, 0],
                startTimeSeconds: 0,
                endTimeSeconds: 1,
                qualityScore: 1
            )
        ]
        let engine = FluidAudioEngine(manager: MockFluidAudioManager(result: upstream))
        try await engine.prepare()

        do {
            _ = try await engine.diarize(audioArray: [0])
            Issue.record("diarize should throw")
        } catch case DiarizationEngineError.invalidEmbedding(let expected, let actual) {
            #expect(expected == 256)
            #expect(actual == 2)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

private enum StubError: Error {
    case unavailable
}

private actor MockFluidAudioManager: FluidAudioManaging {
    let prepareError: (any Error)?
    let processError: (any Error)?
    let result: [TimedSpeakerSegment]

    init(
        prepareError: (any Error)? = nil,
        processError: (any Error)? = nil,
        result: [TimedSpeakerSegment] = []
    ) {
        self.prepareError = prepareError
        self.processError = processError
        self.result = result
    }

    func prepareModels() throws {
        if let prepareError { throw prepareError }
    }

    func process(audio: [Float]) throws -> [TimedSpeakerSegment] {
        if let processError { throw processError }
        result
    }
}
