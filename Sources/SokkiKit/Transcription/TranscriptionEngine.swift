import Foundation

public protocol TranscriptionSegment: Sendable {
    var start: TimeInterval { get }
    var end: TimeInterval { get }
    var text: String { get }
    var isConfirmed: Bool { get }
    var avgLogProb: Float { get }
}

/// 確定セグメントの Sendable な値スナップショット。
/// actor 境界（WhisperKitEngine actor → @MainActor Pipeline）を越えて渡すために使う。
public struct TranscriptionSegmentSnapshot: TranscriptionSegment {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let isConfirmed: Bool
    public let avgLogProb: Float

    public init(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        isConfirmed: Bool = true,
        avgLogProb: Float = 0
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.isConfirmed = isConfirmed
        self.avgLogProb = avgLogProb
    }
}

/// ストリーミング文字起こしの1回分のアップデート。
///
/// - `newlyConfirmed`: このアップデートで新たに確定したセグメント。UI 末尾に追記し、
///   そのまま SwiftData に永続化する（一度だけ emit される）。
/// - `hypothesis`: 現在の未確定テキスト。毎回まるごと置換する（空文字は hypothesis のクリア）。
///
/// WhisperKit の `AudioStreamTranscriber.State`（confirmedSegments / unconfirmedSegments）を
/// 差分ベースの Sendable 値型に落とし込んだもの。
public struct TranscriptionStreamUpdate: Sendable, Equatable {
    public var newlyConfirmed: [TranscriptionSegmentSnapshot]
    public var hypothesis: String

    public init(
        newlyConfirmed: [TranscriptionSegmentSnapshot] = [],
        hypothesis: String = ""
    ) {
        self.newlyConfirmed = newlyConfirmed
        self.hypothesis = hypothesis
    }
}

extension TranscriptionSegmentSnapshot: Equatable {
    public static func == (lhs: TranscriptionSegmentSnapshot, rhs: TranscriptionSegmentSnapshot) -> Bool {
        lhs.start == rhs.start
            && lhs.end == rhs.end
            && lhs.text == rhs.text
            && lhs.isConfirmed == rhs.isConfirmed
            && lhs.avgLogProb == rhs.avgLogProb
    }
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
    ) -> AsyncThrowingStream<TranscriptionStreamUpdate, Error>
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
