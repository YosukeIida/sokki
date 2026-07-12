import Foundation

public protocol TranscriptionSegment: Sendable {
    var start: TimeInterval { get }
    var end: TimeInterval { get }
    var text: String { get }
    var isConfirmed: Bool { get }
    var avgLogProb: Float { get }
}

/// モデル準備（ダウンロード〜メモリロード）の進捗フェーズ。
public enum TranscriptionEngineLoadPhase: Sendable, Equatable {
    /// モデルファイルのダウンロード中。`fractionCompleted` は 0...1。
    case downloading(fractionCompleted: Double)
    /// ダウンロード済みモデルを CoreML にロード中（バイト単位の進捗は取得できない）。
    case loadingIntoMemory
}

public protocol TranscriptionEngine: Actor {
    func prepare(onProgress: @escaping @Sendable (TranscriptionEngineLoadPhase) -> Void) async throws
    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment]
    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<any TranscriptionSegment, Error>
    var isReady: Bool { get }
    var modelIdentifier: String { get }
}

public extension TranscriptionEngine {
    /// 進捗通知が不要な場合の簡易呼び出し。
    func prepare() async throws {
        try await prepare(onProgress: { _ in })
    }
}

enum TranscriptionEngineError: Error {
    case notPrepared
    case modelLoadFailed(underlying: Error)
}
