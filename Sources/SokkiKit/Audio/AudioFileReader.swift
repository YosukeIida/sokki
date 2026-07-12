import AVFoundation

/// 保存済み録音ファイルを 16kHz mono Float32 のサンプル配列へ復号する（P3 バッチ話者分離用）。
///
/// 録音は `AudioFileWriter` により 16kHz mono で書き出される（`.m4a` は AAC）。ここではそれを
/// 読み戻し、必要なら 16kHz mono へ変換して `diarize(audioArray:)` に渡せる形にする。
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

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: processingFormat, to: targetFormat) else {
            return samples(from: buffer)
        }

        let ratio = sampleRate / processingFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return samples(from: buffer)
        }

        var provided = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil {
            return samples(from: buffer)
        }
        return samples(from: outBuffer)
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }
}
