import AVFoundation

/// `AudioFileReader.readMonoSamples` の失敗理由。
enum AudioFileReaderError: Error, LocalizedError {
    /// 16kHz mono への変換コンバータを構築できなかった（フォーマット非対応など）。
    case conversionUnavailable
    /// 変換処理そのものが失敗した。
    case conversionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .conversionUnavailable:
            return "音声フォーマットを 16kHz mono へ変換できませんでした。"
        case .conversionFailed(let error):
            return "音声フォーマットの変換に失敗しました: \(error.localizedDescription)"
        }
    }
}

/// 保存済み録音ファイルを 16kHz mono Float32 のサンプル配列へ復号する（P3 バッチ話者分離用）。
///
/// 録音は `AudioFileWriter` により 16kHz mono で書き出される（`.m4a` は AAC）。ここではそれを
/// 読み戻し、必要なら 16kHz mono へ変換して `diarize(audioArray:)` に渡せる形にする。
enum AudioFileReader {

    /// 指定 URL の音声を 16kHz mono Float32 のサンプル配列として読み込む。
    /// フォーマットが既に 16kHz mono の場合は変換せずそのまま返す。
    ///
    /// 変換コンバータの構築・変換自体が失敗した場合は `AudioFileReaderError` を throw する
    /// （以前は元のフォーマットのサンプルをそのまま無変換で返していたが、サンプルレートが違う
    /// データを 16kHz として扱うと duration 計算や文字起こし・話者分離の時間軸がずれて壊れるため、
    /// 復旧不能な誤り込みより明示的な失敗を優先する。TASK-34 でファイルインポートが多様な
    /// サンプルレート/チャンネル構成の外部ファイルを扱うようになり、このフォールバックが
    /// 発生し得る現実的な経路になったための変更）。
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
            throw AudioFileReaderError.conversionUnavailable
        }

        let ratio = sampleRate / processingFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw AudioFileReaderError.conversionUnavailable
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
        if let error {
            throw AudioFileReaderError.conversionFailed(underlying: error)
        }
        return samples(from: outBuffer)
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }
}
