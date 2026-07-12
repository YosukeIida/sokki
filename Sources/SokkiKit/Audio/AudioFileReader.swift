@preconcurrency import AVFoundation

/// 保存済み録音ファイルを 16kHz mono Float32 のサンプル配列へ復号する（P3 バッチ話者分離用）。
///
/// 録音は `AudioFileWriter` により 16kHz mono で書き出される（`.m4a` は AAC）。ここではそれを
/// 読み戻し、必要なら 16kHz mono へ変換して `diarize(audioArray:)` に渡せる形にする。
enum AudioFileReaderError: Error {
    /// 16kHz mono へのコンバータ／フォーマット生成に失敗した。
    case conversionUnavailable
    /// コンバータ実行中にエラーが発生した。
    case conversionFailed(underlying: Error)
}

enum AudioFileReader {

    /// 指定 URL の音声を 16kHz mono Float32 のサンプル配列として読み込む。
    /// フォーマットが既に 16kHz mono の場合は変換せずそのまま返す。
    static func readMonoSamples(url: URL, sampleRate: Double = 16_000) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let processingFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else {
            return []
        }
        try file.read(into: buffer)

        if processingFormat.sampleRate == sampleRate && processingFormat.channelCount == 1 {
            return samples(from: buffer)
        }

        // 16kHz mono へ変換する。変換できない場合は誤ったサンプルレートのサンプルを
        // diarize（16kHz 前提）へ渡すと時刻ずれ・embedding 劣化を招くため、フォールバックせず throw する。
        // 呼び出し側（runDiarizationIfEnabled）は graceful degradation で握りつぶすため安全。
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: processingFormat, to: targetFormat) else {
            throw AudioFileReaderError.conversionUnavailable
        }

        let ratio = sampleRate / processingFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw AudioFileReaderError.conversionUnavailable
        }

        // AVAudioConverterInputBlock は @Sendable のため、可変フラグは Sendable なボックスに包む。
        // 入力（buffer）は一度だけ供給し、以降は noDataNow を返す。
        let state = ConverterInputState()
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if state.provided {
                status.pointee = .noDataNow
                return nil
            }
            state.provided = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            throw AudioFileReaderError.conversionFailed(underlying: error)
        }
        return samples(from: outBuffer)
    }

    /// AVAudioConverterInputBlock（@Sendable）内で使う可変フラグの入れ物。
    /// convert(to:error:withInputFrom:) はブロックを同期的に呼ぶため実際の並行アクセスは無い。
    private final class ConverterInputState: @unchecked Sendable {
        var provided = false
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }
}
