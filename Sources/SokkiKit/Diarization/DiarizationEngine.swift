import Foundation

public struct DiarizationSegment: Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let speakerID: String       // エンジン依存の内部ラベル（FluidAudio は "S1" 等、SpeakerKit は "SPEAKER_00" 等）。下流は不透明なキーとして扱う
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

enum DiarizationEngineError: Error, LocalizedError {
    case notPrepared
    case modelLoadFailed(underlying: Error)
    case diarizationFailed(underlying: Error)
    case invalidEmbedding(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "話者分離モデルが準備されていません。"
        case .modelLoadFailed(let error):
            return "話者分離モデルを取得または読み込みできませんでした: \(error.localizedDescription)"
        case .diarizationFailed(let error):
            return "話者分離に失敗しました: \(error.localizedDescription)"
        case .invalidEmbedding(let expected, let actual):
            return "話者 embedding の次元が不正です（期待値: \(expected)、実際: \(actual)）。"
        }
    }
}
