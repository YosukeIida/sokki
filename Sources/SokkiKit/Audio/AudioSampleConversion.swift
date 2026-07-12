import AVFoundation

/// マイク / システム音声の両経路で共用する 16kHz mono Float32 変換とレベル計測ユーティリティ。
///
/// すべて `nonisolated` な純粋関数（`AVAudioConverter` を引数で受け取り副作用を持たない）なので、
/// アクター上でも専用 IO キュー上でも同じ実装を安全に呼び出せる。レベル値はマイク経路と同じ
/// dBFS RMS（-60...0）に統一する。
enum AudioSampleConversion {

    /// 文字起こしエンジンが要求するサンプルレート。
    static let targetSampleRate: Double = 16_000

    /// 16kHz / mono / Float32 / 非インターリーブの変換先フォーマット。
    static func makeTargetFormat() -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    /// 入力バッファを `targetFormat`（16kHz mono）へ変換する。1 コールバック分の変換に閉じる。
    static func convertToBuffer(
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

    /// 変換済みバッファの channel 0 を `[Float]` として取り出す。
    static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }

    /// dBFS RMS レベル（-60...0）。無音・空配列は -60 を返す。
    static func rmsLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -60 }
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        let db = rms > 0 ? 20 * log10(rms) : -60
        return max(-60, min(0, db))
    }
}
