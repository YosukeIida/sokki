import Foundation

public protocol TranscriptionSegment: Sendable {
    var start: TimeInterval { get }
    var end: TimeInterval { get }
    var text: String { get }
    var isConfirmed: Bool { get }
    var avgLogProb: Float { get }
}

public protocol TranscriptionEngine: Actor {
    func prepare() async throws
    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment]
    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<any TranscriptionSegment, Error>
    var isReady: Bool { get }
    var modelIdentifier: String { get }
}

enum TranscriptionEngineError: Error {
    case notPrepared
    case modelLoadFailed(underlying: Error)
}
