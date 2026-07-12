import Foundation
import WhisperKit

private func stripSpecialTokens(_ raw: String) -> String {
    // Whisper 特殊トークンを除去（<|...|> 形式）。前後空白のトリムはしない。
    raw.replacing(#/<\|[^|]+\|>/#, with: "")
}

private func cleanText(_ raw: String) -> String {
    stripSpecialTokens(raw).trimmingCharacters(in: .whitespacesAndNewlines)
}

actor WhisperKitEngine: TranscriptionEngine {

    private var whisperKit: WhisperKit?
    // nil = デバイスに合った推奨モデルを自動選択
    private let modelVariant: String?

    private(set) var isReady = false

    var modelIdentifier: String { "whisperkit/\(modelVariant ?? "auto")" }

    init(modelVariant: String? = nil) {
        self.modelVariant = modelVariant
    }

    func prepare(onProgress: @escaping @Sendable (TranscriptionEngineLoadPhase) -> Void) async throws {
        do {
            // WhisperKit(model:) の既定初期化ではダウンロード中の進捗が一切コールバックされないため、
            // ダウンロードとメモリロードを明示的に分離し、ダウンロードの進捗（バイト単位）を報告する。
            let resolvedVariant: String
            if let modelVariant {
                resolvedVariant = modelVariant
            } else {
                resolvedVariant = await WhisperKit.recommendedRemoteModels().default
            }

            let modelFolder = try await WhisperKit.download(
                variant: resolvedVariant,
                progressCallback: { progress in
                    onProgress(.downloading(fractionCompleted: progress.fractionCompleted))
                }
            )

            onProgress(.loadingIntoMemory)

            whisperKit = try await WhisperKit(
                WhisperKitConfig(model: resolvedVariant, modelFolder: modelFolder.path, load: true)
            )
            isReady = true
        } catch {
            throw TranscriptionEngineError.modelLoadFailed(underlying: error)
        }
    }

    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment] {
        guard let wk = whisperKit else { throw TranscriptionEngineError.notPrepared }

        let results: [TranscriptionResult] = try await wk.transcribe(audioArray: audioArray)
        return results.flatMap(\.segments).compactMap { seg in
            let text = cleanText(seg.text)
            guard !text.isEmpty else { return nil }
            return TranscriptionSegmentSnapshot(
                start: TimeInterval(seg.start),
                end: TimeInterval(seg.end),
                text: text,
                isConfirmed: true,
                avgLogProb: seg.avgLogprob
            )
        }
    }

    // MARK: - Streaming (confirmed boundary)

    /// 確定境界を前進させながらリアルタイムに文字起こしする。
    ///
    /// WhisperKit の `AudioStreamTranscriber` と同じ戦略を、当アプリの
    /// `AsyncStream<AudioChunk>`（16kHz mono Float32・mic / system 両対応）供給に合わせて再実装する:
    /// 全録音を保持するバッファを持ち、直近の確定境界 `lastConfirmedEnd` から末尾までを
    /// `clipTimestamps` で再デコードする。末尾 `requiredSegments` 本を hypothesis として保持し、
    /// それより前を確定する。ストリーム終了時に残りを flush して確定する。
    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptionStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            // このアクター内で生成される非構造化 Task はアクター隔離を継承する。
            Task {
                do {
                    var tracker = ConfirmedBoundaryTracker(requiredSegments: Self.requiredSegmentsForConfirmation)
                    var buffer: [Float] = []
                    var lastProcessedCount = 0
                    let minNewSamples = Int(Self.minNewSecondsPerStep * Float(Self.sampleRate))

                    for await chunk in audioChunks {
                        buffer.append(contentsOf: chunk.samples)

                        // 直近の処理以降に十分な新規音声が溜まってからデコードする（過剰デコード抑制）。
                        guard buffer.count - lastProcessedCount >= minNewSamples else { continue }
                        lastProcessedCount = buffer.count

                        let decoded = try await decodeSegments(buffer, clipStart: tracker.lastConfirmedEnd)
                        let update = tracker.ingest(decoded)
                        // 変化がない空アップデートは送らない（UI 更新の無駄打ちを避ける）。
                        if !update.newlyConfirmed.isEmpty || !update.hypothesis.isEmpty {
                            continuation.yield(update)
                        }
                    }

                    // フラッシュ: バッファ末尾の残りを確定して hypothesis をクリアする。
                    if !buffer.isEmpty {
                        let decoded = try await decodeSegments(buffer, clipStart: tracker.lastConfirmedEnd)
                        let update = tracker.flush(decoded)
                        continuation.yield(update)
                    } else {
                        // 何も無くても hypothesis を確実にクリアする。
                        continuation.yield(TranscriptionStreamUpdate(newlyConfirmed: [], hypothesis: ""))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// 指定した秒位置 `clipStart` から末尾までを再デコードし、境界ロジック用の生セグメント列を返す。
    private func decodeSegments(_ samples: [Float], clipStart: Float) async throws -> [DecodedSegment] {
        guard let wk = whisperKit else { throw TranscriptionEngineError.notPrepared }

        var options = DecodingOptions()
        options.clipTimestamps = [clipStart]

        let results = try await wk.transcribe(audioArray: samples, decodeOptions: options)
        return results.flatMap(\.segments).map { seg in
            DecodedSegment(
                start: seg.start,
                end: seg.end,
                text: stripSpecialTokens(seg.text),
                avgLogProb: seg.avgLogprob
            )
        }
    }

    // MARK: - Streaming tuning constants

    /// 16kHz mono。AudioChunk の仕様と一致。
    private static let sampleRate = 16_000
    /// 末尾に保持して確定を保留するセグメント数（WhisperKit 既定と同じ）。
    private static let requiredSegmentsForConfirmation = 2
    /// 1回のデコードに必要な新規音声の最小秒数。
    private static let minNewSecondsPerStep: Float = 1.0
}
