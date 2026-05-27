import Foundation

public struct DiarizationSegment: Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let speakerID: String       // "SPEAKER_00" 等（エンジン内部ラベル）
    public let embedding: [Float]?     // 256-dim WeSpeaker ResNet34
}

public struct DiarizationResult: Sendable {
    public let segments: [DiarizationSegment]
    public let numberOfSpeakers: Int
}

public protocol DiarizationEngine: Actor {
    func prepare() async throws
    func diarize(audioArray: [Float]) async throws -> DiarizationResult
    var isReady: Bool { get }
}

enum DiarizationEngineError: Error {
    case notPrepared
    case modelLoadFailed(underlying: Error)
}
