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
    func prepare() async throws
    func prepare(onProgress: @escaping @Sendable (TranscriptionEngineLoadPhase) -> Void) async throws
    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment]
    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<any TranscriptionSegment, Error>
    /// 文字起こし言語を設定する。AppSettingsModel.transcriptionLanguage の値（"auto" / "ja" / ... ）をそのまま渡す。
    /// "auto" または nil の場合は自動検出。デフォルト実装は何もしない（既存 conformer のソース互換性を保つ）。
    func setTranscriptionLanguage(_ settingValue: String?) async
    var isReady: Bool { get }
    var modelIdentifier: String { get }
}

// `prepare()` と `prepare(onProgress:)` は互いのデフォルト実装を提供する。
// 適合型はどちらか一方だけを実装すればよい（両方未実装のままだと無限再帰になる）。
// 旧シグネチャ `prepare()` だけを実装した既存の外部 conformer のソース互換性を保つため。
public extension TranscriptionEngine {
    func prepare() async throws {
        try await prepare(onProgress: { _ in })
    }

    func prepare(onProgress: @escaping @Sendable (TranscriptionEngineLoadPhase) -> Void) async throws {
        try await prepare()
    }

    func setTranscriptionLanguage(_ settingValue: String?) async {}
}

enum TranscriptionEngineError: Error {
    case notPrepared
    case modelLoadFailed(underlying: Error)
}
