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
    /// `AsyncStream<AudioChunk>`（16kHz mono Float32・mic / system 両対応）供給に合わせて再実装する。
    ///
    /// 構造は参照実装（`AudioStreamTranscriber`）と同じく「入力の集約」と「定期デコード」を分離する:
    /// - **drain Task**: 入力ストリームを継続的に読み出し、専用アクター `AudioSampleAccumulator` の
    ///   単一サンプルバッファへ即時集約する。これにより `AsyncStream` 内部の無制限バッファに
    ///   未処理チャンクが溜まり続ける（＝全量バッファとの二重保持・遅延の際限ない増大）のを防ぐ。
    /// - **デコードループ**: バッファのスナップショットに対して、直近の確定境界 `lastConfirmedEnd` から
    ///   末尾までを `clipTimestamps` で再デコードする。末尾 `requiredSegments` 本を hypothesis として
    ///   保持し、それより前を確定する。ストリーム終了時に残りを flush して確定する。
    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptionStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            // このアクター内で生成される非構造化 Task はアクター隔離を継承する。
            let producer = Task {
                let accumulator = AudioSampleAccumulator()

                // 入力ストリームを専用 Task で drain して単一バッファへ即時集約する（MAJOR-1）。
                let drainTask = Task {
                    for await chunk in audioChunks {
                        await accumulator.append(chunk.samples)
                    }
                    await accumulator.finish()
                }
                defer { drainTask.cancel() }

                var tracker = ConfirmedBoundaryTracker(requiredSegments: Self.requiredSegmentsForConfirmation)
                var lastProcessedCount = 0
                let minNewSamples = Int(Self.minNewSecondsPerStep * Float(Self.sampleRate))
                var hypothesisShown = false

                // 直前が非空で今回が空なら、hypothesis を画面から消すため空更新も送る（参照実装と同じ挙動）。
                func emit(_ update: TranscriptionStreamUpdate) {
                    let hasContent = !update.newlyConfirmed.isEmpty || !update.hypothesis.isEmpty
                    guard hasContent || hypothesisShown else { return }
                    continuation.yield(update)
                    hypothesisShown = !update.hypothesis.isEmpty
                }

                do {
                    var reachedEnd = false
                    while !Task.isCancelled {
                        let finished = await accumulator.isFinished
                        let count = await accumulator.count

                        if !finished, count - lastProcessedCount >= minNewSamples {
                            let buffer = await accumulator.snapshot()
                            lastProcessedCount = buffer.count
                            let decoded = try await decodeSegments(buffer, clipStart: tracker.lastConfirmedEnd)
                            emit(tracker.ingest(decoded))
                        } else if finished {
                            reachedEnd = true
                            break
                        } else {
                            // 新規音声が溜まるまで少し待つ（参照実装同様のポーリング）。
                            try await Task.sleep(for: .milliseconds(Self.pollIntervalMillis))
                        }
                    }

                    if reachedEnd {
                        // フラッシュ: バッファ末尾の残りを確定して hypothesis をクリアする。
                        let finalBuffer = await accumulator.snapshot()
                        let decoded = finalBuffer.isEmpty
                            ? []
                            : try await decodeSegments(finalBuffer, clipStart: tracker.lastConfirmedEnd)
                        continuation.yield(tracker.flush(decoded))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in producer.cancel() }
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
    /// 新規音声が最小秒数に満たないときのポーリング間隔（ミリ秒）。
    private static let pollIntervalMillis = 100
}

/// 入力 `AsyncStream<AudioChunk>` を drain して単一のサンプルバッファへ集約する軽量アクター。
///
/// デコードが実時間より遅くなっても、入力チャンクは即座にここへ吸い上げられるため、
/// `AsyncStream` 内部の無制限バッファに未処理チャンクが積み上がらない。デコードループは
/// 常に最新の `snapshot()` に対して回せる（＝再デコードで自然にキャッチアップする）。
private actor AudioSampleAccumulator {
    private(set) var samples: [Float] = []
    private(set) var isFinished = false

    func append(_ newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
    }

    func finish() {
        isFinished = true
    }

    var count: Int { samples.count }

    func snapshot() -> [Float] { samples }
}
