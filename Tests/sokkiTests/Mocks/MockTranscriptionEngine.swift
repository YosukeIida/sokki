import Foundation
@testable import SokkiKit

struct MockSegment: TranscriptionSegment {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var isConfirmed: Bool
    var avgLogProb: Float

    init(text: String, start: TimeInterval = 0, end: TimeInterval = 1, isConfirmed: Bool = true) {
        self.text = text
        self.start = start
        self.end = end
        self.isConfirmed = isConfirmed
        self.avgLogProb = -0.1
    }
}

actor MockTranscriptionEngine: TranscriptionEngine {
    private(set) var isReady = false
    var modelIdentifier = "mock"

    var prepareCallCount = 0
    var transcribeCallCount = 0
    var stubbedSegments: [any TranscriptionSegment] = [MockSegment(text: "テストテキスト")]
    var shouldThrowOnPrepare = false
    var shouldThrowOnTranscribe = false

    func prepare() async throws {
        prepareCallCount += 1
        if shouldThrowOnPrepare {
            throw TranscriptionEngineError.modelLoadFailed(underlying: NSError(domain: "mock", code: -1))
        }
        isReady = true
    }

    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment] {
        transcribeCallCount += 1
        if shouldThrowOnTranscribe {
            throw TranscriptionEngineError.notPrepared
        }
        return stubbedSegments
    }

    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<any TranscriptionSegment, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for seg in stubbedSegments {
                    continuation.yield(seg)
                }
                continuation.finish()
            }
        }
    }
}

actor MockAudioCaptureManager {
    private var micCont: AsyncStream<AudioChunk>.Continuation?
    private(set) var micStream: AsyncStream<AudioChunk>
    private(set) var systemStream: AsyncStream<AudioChunk>
    private(set) var micLevelStream: AsyncStream<Float>
    private(set) var systemLevelStream: AsyncStream<Float>

    var startCallCount = 0
    var stopCallCount = 0

    init() {
        var mc: AsyncStream<AudioChunk>.Continuation!
        micStream    = AsyncStream { mc = $0 }
        systemStream = AsyncStream { _ in }
        micLevelStream    = AsyncStream { _ in }
        systemLevelStream = AsyncStream { _ in }
        micCont = mc
    }

    func startCapture(mode: AudioCaptureManager.CaptureMode) async throws {
        startCallCount += 1
    }

    func stopCapture() async {
        stopCallCount += 1
        micCont?.finish()
    }

    func sendChunk(_ samples: [Float]) {
        let chunk = AudioChunk(lane: .microphone, samples: samples, capturedAt: Date())
        micCont?.yield(chunk)
    }
}
