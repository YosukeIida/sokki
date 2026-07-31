@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech
import os

// MARK: - Pure mapping (Speech 非依存・テスト可能)

/// SpeechTranscriber の1件の結果を `TranscriptionStreamUpdate` へ写像する純粋関数。
///
/// - `isFinal == true`（確定）: `newlyConfirmed` に1セグメントを載せ、hypothesis をクリアする。
///   テキストが空（区切りのみ等）の確定は、画面の未確定テキストを消すため空アップデートにする。
/// - `isFinal == false`（volatile / 暫定）: hypothesis をまるごと置換する。
///
/// WhisperKit エンジンの2系統（Hypothesis / Confirmed）表示にそのまま乗せられる形にする。
func speechAnalyzerStreamUpdate(
    isFinal: Bool,
    text: String,
    start: TimeInterval,
    end: TimeInterval
) -> TranscriptionStreamUpdate {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if isFinal {
        guard !trimmed.isEmpty else {
            return TranscriptionStreamUpdate(newlyConfirmed: [], hypothesis: "")
        }
        return TranscriptionStreamUpdate(
            newlyConfirmed: [
                TranscriptionSegmentSnapshot(
                    start: start,
                    end: end,
                    text: trimmed,
                    isConfirmed: true,
                    avgLogProb: 0
                )
            ],
            hypothesis: ""
        )
    } else {
        return TranscriptionStreamUpdate(newlyConfirmed: [], hypothesis: trimmed)
    }
}

// MARK: - Errors

enum SpeechAnalyzerEngineError: Error {
    case notPrepared
    /// このデバイス／OS で SpeechTranscriber が利用できない。
    case speechRecognitionUnavailable
    /// 要求ロケールが SpeechTranscriber の対応ロケールに含まれない。
    case unsupportedLocale(String)
    /// モジュールに適合する解析用オーディオフォーマットが取得できなかった。
    case audioFormatUnavailable
    /// モデルアセットのダウンロード／インストールに失敗。
    case assetInstallationFailed(underlying: Error)
}

// MARK: - Buffer converter

/// 入力 `AVAudioPCMBuffer` を SpeechAnalyzer が要求するフォーマットへ変換する軽量ヘルパー。
///
/// 実装は swift-scribe（FluidInference/swift-scribe）の `BufferConverter` を踏襲する。
/// SpeechAnalyzer の要求フォーマットは入力（16kHz mono Float32）と一致しないことが多く、
/// 変換せずに供給すると「ビルドは通るが無音扱いで文字起こしされない」silent failure になる。
final class BufferConverter {
    enum ConversionError: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            // 先頭サンプルの品質を犠牲にしてでもタイムスタンプのドリフトを避ける。
            converter?.primeMethod = .none
        }
        guard let converter else { throw ConversionError.failedToCreateConverter }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard
            let conversionBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat, frameCapacity: frameCapacity)
        else {
            throw ConversionError.failedToCreateConversionBuffer
        }

        var nsError: NSError?
        let bufferProcessedLock = OSAllocatedUnfairLock(initialState: false)

        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            let wasProcessed = bufferProcessedLock.withLock { bufferProcessed -> Bool in
                let wasProcessed = bufferProcessed
                bufferProcessed = true
                return wasProcessed
            }
            inputStatusPointer.pointee = wasProcessed ? .noDataNow : .haveData
            return wasProcessed ? nil : buffer
        }

        guard status != .error else { throw ConversionError.conversionFailed(nsError) }
        return conversionBuffer
    }
}

/// 16kHz mono Float32 の `[Float]`（既存パイプラインの形式）を `AVAudioPCMBuffer` に載せる。
/// 変換前の元フォーマット。SpeechAnalyzer へ渡す前に `BufferConverter` で要求形式へ変換する。
func makeSourceBuffer(_ samples: [Float], sampleRate: Double = 16_000) -> AVAudioPCMBuffer? {
    guard !samples.isEmpty else { return nil }
    guard
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
    else {
        return nil
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { src in
        if let base = src.baseAddress, let dst = buffer.floatChannelData?[0] {
            dst.update(from: base, count: samples.count)
        }
    }
    return buffer
}

// MARK: - Engine

/// Apple の Speech framework（macOS 26+）の新 API（`SpeechAnalyzer` / `SpeechTranscriber` /
/// `AnalyzerInput`）を用いた文字起こしエンジン。`TranscriptionEngine` に準拠し、WhisperKit と
/// ドロップイン交換できる。
///
/// - 対応は macOS 26.0 以降。型全体を `@available(macOS 26.0, *)` でガードするため、
///   deployment target 15.0 のままでもモジュールはビルドできる（呼び出し側で `#available` 分岐）。
/// - `prepare()` で対応ロケール確認 → モデルアセットのインストール要求 → ロケール確保を行う。
/// - ストリーミングは volatile（暫定）/ finalized（確定）結果を `TranscriptionStreamUpdate` の
///   hypothesis / newlyConfirmed に写像する（TASK-14 の2系統表示にそのまま乗る）。
@available(macOS 26.0, *)
actor SpeechAnalyzerEngine: TranscriptionEngine {

    /// 起動時に使用するロケール（`prepare()` で対応ロケールへ解決され得る）。
    private var locale: Locale

    private(set) var isReady = false

    var modelIdentifier: String { "speechanalyzer/\(locale.identifier(.bcp47))" }

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.locale = locale
    }

    /// 文字起こし言語を切り替える。次回 `prepare()` から反映される。
    /// （`TranscriptionEngine` protocol 外のエンジン固有 API）
    func setTranscriptionLanguage(_ locale: Locale) {
        self.locale = locale
        isReady = false
    }

    // MARK: prepare

    func prepare(onProgress: @escaping @Sendable (TranscriptionEngineLoadPhase) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechAnalyzerEngineError.speechRecognitionUnavailable
        }

        // 対応ロケールへ解決（例: "ja-JP" → 対応する等価ロケール）。
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == resolved.identifier(.bcp47) }) else {
            throw SpeechAnalyzerEngineError.unsupportedLocale(locale.identifier)
        }
        locale = resolved

        // アセットのインストール要求（必要な場合のみ）。ダウンロード進捗を報告する。
        let probe = makeTranscriber(volatile: true)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                onProgress(.downloading(fractionCompleted: 0))
                let progress = request.progress
                let pollTask = Task { @Sendable in
                    while !Task.isCancelled {
                        onProgress(.downloading(fractionCompleted: progress.fractionCompleted))
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                defer { pollTask.cancel() }
                try await request.downloadAndInstall()
            }
        } catch {
            throw SpeechAnalyzerEngineError.assetInstallationFailed(underlying: error)
        }

        onProgress(.loadingIntoMemory)
        try await reserveLocaleIfNeeded(resolved)

        isReady = true
    }

    /// ロケールが未確保なら確保する（確保済み or 既に上限内なら何もしない）。
    private func reserveLocaleIfNeeded(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            return
        }
        do {
            _ = try await AssetInventory.reserve(locale: locale)
        } catch {
            throw SpeechAnalyzerEngineError.assetInstallationFailed(underlying: error)
        }
    }

    // MARK: batch

    func transcribe(audioArray: [Float]) async throws -> [any TranscriptionSegment] {
        guard isReady else { throw SpeechAnalyzerEngineError.notPrepared }
        guard !audioArray.isEmpty else { return [] }

        let session = try await makeSession(volatile: false)

        // 結果は入力供給と並行して届くため、確定結果を収集するタスクを先に起動する。
        let collector = Task { () throws -> [TranscriptionSegmentSnapshot] in
            var segments: [TranscriptionSegmentSnapshot] = []
            for try await result in session.transcriber.results where result.isFinal {
                let (start, end) = Self.seconds(result.range)
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                segments.append(
                    TranscriptionSegmentSnapshot(start: start, end: end, text: text, isConfirmed: true, avgLogProb: 0)
                )
            }
            return segments
        }

        if let input = try makeAnalyzerInput(audioArray, session: session) {
            session.inputContinuation.yield(input)
        }
        session.inputContinuation.finish()
        try await session.analyzer.finalizeAndFinishThroughEndOfInput()

        return try await collector.value
    }

    // MARK: streaming

    /// volatile（暫定）/ finalized（確定）結果をリアルタイムに `TranscriptionStreamUpdate` へ写像して流す。
    ///
    /// WhisperKitEngine と同じく「入力の drain（供給）」と「結果の消費」を分離する:
    /// - **feed Task**: 入力チャンクを解析用フォーマットへ変換して `AnalyzerInput` を供給する。
    ///   ストリーム終端で入力を閉じ、`finalizeAndFinishThroughEndOfInput()` を呼ぶ。
    /// - **消費ループ**: `transcriber.results` を読み、確定→newlyConfirmed / 暫定→hypothesis に写像する。
    func transcribeStream(
        audioChunks: AsyncStream<AudioChunk>
    ) -> AsyncThrowingStream<TranscriptionStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    guard isReady else { throw SpeechAnalyzerEngineError.notPrepared }
                    let session = try await makeSession(volatile: true)

                    // 入力を drain して解析器へ供給する専用 Task（アクター隔離を継承する）。
                    let feedTask = Task {
                        for await chunk in audioChunks {
                            if let input = try? makeAnalyzerInput(chunk.samples, session: session) {
                                session.inputContinuation.yield(input)
                            }
                        }
                        session.inputContinuation.finish()
                        try? await session.analyzer.finalizeAndFinishThroughEndOfInput()
                    }
                    defer { feedTask.cancel() }

                    for try await result in session.transcriber.results {
                        let (start, end) = Self.seconds(result.range)
                        let text = String(result.text.characters)
                        continuation.yield(
                            speechAnalyzerStreamUpdate(
                                isFinal: result.isFinal, text: text, start: start, end: end)
                        )
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

    // MARK: - Session

    /// 1回の解析セッションで使うオブジェクト一式。アクター内でのみ生成・使用する。
    private struct Session {
        let analyzer: SpeechAnalyzer
        let transcriber: SpeechTranscriber
        let analyzerFormat: AVAudioFormat
        let converter: BufferConverter
        let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    }

    private func makeTranscriber(volatile: Bool) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: volatile ? [.volatileResults] : [],
            attributeOptions: [.audioTimeRange]
        )
    }

    private func makeSession(volatile: Bool) async throws -> Session {
        let transcriber = makeTranscriber(volatile: volatile)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechAnalyzerEngineError.audioFormatUnavailable
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)
        return Session(
            analyzer: analyzer,
            transcriber: transcriber,
            analyzerFormat: format,
            converter: BufferConverter(),
            inputContinuation: continuation
        )
    }

    /// 16kHz mono の `[Float]` を解析器フォーマットへ変換して `AnalyzerInput` を生成する。
    private func makeAnalyzerInput(_ samples: [Float], session: Session) throws -> AnalyzerInput? {
        guard let source = makeSourceBuffer(samples) else { return nil }
        let converted = try session.converter.convertBuffer(source, to: session.analyzerFormat)
        return AnalyzerInput(buffer: converted)
    }

    /// `CMTimeRange` を秒（開始・終了）へ変換する。非有限値は 0 相当へ丸める。
    private static func seconds(_ range: CMTimeRange) -> (TimeInterval, TimeInterval) {
        let rawStart = range.start.seconds
        let rawEnd = range.end.seconds
        let start = rawStart.isFinite ? rawStart : 0
        let end = rawEnd.isFinite ? max(start, rawEnd) : start
        return (start, end)
    }
}
