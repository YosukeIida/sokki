import Foundation
import WhisperKit

struct WhisperSegment: TranscriptionSegment {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let isConfirmed: Bool
    let avgLogProb: Float
}

private func cleanText(_ raw: String) -> String {
    // Whisper 特殊トークンを除去（<|...|> 形式）
    let cleaned = raw.replacing(#/<\|[^|]+\|>/#, with: "")
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func prepare() async throws {
        do {
            whisperKit = try await WhisperKit(model: modelVariant)
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
            return WhisperSegment(
                start: TimeInterval(seg.start),
                end: TimeInterval(seg.end),
                text: text,
                isConfirmed: true,
                avgLogProb: seg.avgLogprob ?? 0
            )
        }
    }

    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<any TranscriptionSegment, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var buffer: [Float] = []
                let windowSamples = Int(30.0 * 16_000)   // 30 秒
                let overlapSamples = Int(5.0 * 16_000)   // 5 秒オーバーラップ

                for await chunk in audioChunks {
                    buffer.append(contentsOf: chunk.samples)

                    if buffer.count >= windowSamples {
                        let segments = try await transcribe(audioArray: buffer)
                        for seg in segments {
                            continuation.yield(seg)
                        }
                        buffer = Array(buffer.suffix(overlapSamples))
                    }
                }

                // フラッシュ: バッファ残を処理
                if !buffer.isEmpty {
                    let segments = try await transcribe(audioArray: buffer)
                    for seg in segments { continuation.yield(seg) }
                }
                continuation.finish()
            }
        }
    }
}
