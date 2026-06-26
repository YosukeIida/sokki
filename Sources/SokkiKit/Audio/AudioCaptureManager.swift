import AVFoundation

public enum AudioLane: Sendable {
    case microphone
    case system
}

public struct AudioChunk: Sendable {
    public let lane: AudioLane
    public let samples: [Float]   // 16kHz, mono, Float32
    public let capturedAt: Date
}

actor AudioCaptureManager {

    enum CaptureMode: String {
        case micOnly    = "mic"
        case systemOnly = "system"
        case both       = "both"
    }

    enum CaptureError: Error {
        case audioEngineStartFailed(Error)
        case systemAudioRequiresPhase2
    }

    private var micContinuation:      AsyncStream<AudioChunk>.Continuation?
    private var systemContinuation:   AsyncStream<AudioChunk>.Continuation?
    private var micLevelContinuation: AsyncStream<Float>.Continuation?

    private(set) var micStream:      AsyncStream<AudioChunk>
    private(set) var systemStream:   AsyncStream<AudioChunk>
    private(set) var micLevelStream: AsyncStream<Float>
    private(set) var systemLevelStream: AsyncStream<Float>

    private var audioEngine: AVAudioEngine?
    private var fileWriter: AudioFileWriter?
    private let targetSampleRate: Double = 16_000

    init() {
        var micCont:    AsyncStream<AudioChunk>.Continuation!
        var sysCont:    AsyncStream<AudioChunk>.Continuation!
        var micLvlCont: AsyncStream<Float>.Continuation!
        var sysLvlCont: AsyncStream<Float>.Continuation!

        micStream          = AsyncStream { micCont    = $0 }
        systemStream       = AsyncStream { sysCont    = $0 }
        micLevelStream     = AsyncStream { micLvlCont = $0 }
        systemLevelStream  = AsyncStream { sysLvlCont = $0 }

        micContinuation      = micCont
        systemContinuation   = sysCont
        micLevelContinuation = micLvlCont
        // systemLevel は Phase 2 で使う (sysLvlCont を保持するだけ)
        _ = sysLvlCont
    }

    func startCapture(mode: CaptureMode, outputURL: URL? = nil) async throws {
        guard mode == .micOnly else {
            throw CaptureError.systemAudioRequiresPhase2
        }
        // 2回目以降の録音のために新しいストリームを作り直す（AsyncStream は使い捨て）
        resetStreams()
        try await startMicCapture(outputURL: outputURL)
    }

    private func resetStreams() {
        var micCont:    AsyncStream<AudioChunk>.Continuation!
        var micLvlCont: AsyncStream<Float>.Continuation!

        micStream      = AsyncStream { micCont    = $0 }
        micLevelStream = AsyncStream { micLvlCont = $0 }

        micContinuation      = micCont
        micLevelContinuation = micLvlCont
    }

    func stopCapture() async {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        // tap 停止後にファイルを閉じる（書き込み中の競合は AudioFileWriter のロックで防ぐ）
        fileWriter?.close()
        fileWriter = nil
        // ストリームを閉じる → transcribeStream の for-await ループが終了し、フラッシュが走る
        micContinuation?.finish()
        micContinuation = nil
    }

    // MARK: - Private

    private func startMicCapture(outputURL: URL?) async throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // ネイティブフォーマットでタップし、16kHz Float32 に変換
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            return
        }

        // 出力先が指定されていれば録音ファイルを開く（P1-1）。失敗しても録音・文字起こしは継続。
        if let outputURL {
            self.fileWriter = try? AudioFileWriter(url: outputURL, processingFormat: targetFormat)
        }
        let writer = self.fileWriter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let outBuffer = self.convertToBuffer(buffer, using: converter, to: targetFormat) else { return }
            // 音声スレッドで同期書き込み（順序保証）。
            writer?.write(outBuffer)
            let converted = self.samples(from: outBuffer)
            let capturedAt = Date()
            Task {
                await self.dispatchMic(samples: converted, capturedAt: capturedAt)
            }
        }

        self.audioEngine = engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw CaptureError.audioEngineStartFailed(error)
        }
    }

    private nonisolated func convertToBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: max(frameCapacity, 1)
        ) else { return nil }

        var error: NSError?
        var inputProvided = false
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil else { return nil }
        return outBuffer
    }

    private nonisolated func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }

    private func dispatchMic(samples: [Float], capturedAt: Date) {
        let chunk = AudioChunk(lane: .microphone, samples: samples, capturedAt: capturedAt)
        micContinuation?.yield(chunk)
        micLevelContinuation?.yield(rmsLevel(samples))
    }

    private nonisolated func rmsLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -60 }
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        let db = rms > 0 ? 20 * log10(rms) : -60
        return max(-60, min(0, db))
    }
}
