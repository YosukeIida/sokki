@preconcurrency import AVFoundation

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
        let buffer = try readAllFrames(from: file, capacity: frameCount)

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
        // 入力（buffer）は一度だけ供給し、以降は endOfStream を返す。noDataNow だとサンプルレート
        // 変換器が内部に保持する末尾サンプルが flush されず、変換結果の末尾が欠落する。
        let state = ConverterInputState()
        var collected: [Float] = []
        while true {
            outBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
                if state.provided {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                state.provided = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if let error {
                throw AudioFileReaderError.conversionFailed(underlying: error)
            }
            collected.append(contentsOf: samples(from: outBuffer))
            switch status {
            case .haveData, .inputRanDry:
                // haveData: 出力バッファ容量に収まりきらなかった場合は続けて排出する。
                // inputRanDry: 入力ブロックは noDataNow を返さないため通常到達しないが、
                // 到達しても endOfStream まで継続して末尾 flush を確実にする。
                // いずれも進捗（出力）が無ければ打ち切る（無限ループ防止の保険）。
                if outBuffer.frameLength == 0 { return collected }
            case .endOfStream:
                return collected
            case .error:
                // NSError が nil のまま .error が返った場合。途中までのサンプルを返すと
                // 欠落した音声で diarize してしまうため throw する（上流は graceful degradation）。
                throw AudioFileReaderError.conversionFailed(underlying: NSError(
                    domain: "com.sokki.AudioFileReader",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "AVAudioConverter returned .error without NSError"]
                ))
            @unknown default:
                return collected
            }
        }
    }

    /// ファイルの全フレームを 1 つのバッファへ読み切る。
    /// `AVAudioFile.read(into:)` は 1 回の呼び出しで frameCapacity まで埋める保証が無く
    /// （実測: 16,000 フレームの WAV が 15,360 + 640 の 2 回に分かれる）、
    /// 1 回読みでは末尾が欠落するためループで読み進める。
    private static func readAllFrames(
        from file: AVAudioFile,
        capacity: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        let format = file.processingFormat
        guard let full = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
              let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
            throw AudioFileReaderError.conversionUnavailable
        }
        // EOF 到達後にさらに read すると nilError を throw するため、framePosition で読了を判定する。
        while file.framePosition < file.length {
            try file.read(into: chunk)
            let n = Int(chunk.frameLength)
            guard n > 0 else { break }   // 進捗なし（保険: 無限ループ防止）
            let offset = Int(full.frameLength)
            // file.length ベースの capacity を超えることは無いはずだが、保険として打ち切る。
            guard offset + n <= Int(full.frameCapacity) else { break }
            if let src = chunk.floatChannelData, let dst = full.floatChannelData {
                for ch in 0..<Int(format.channelCount) {
                    (dst[ch] + offset).update(from: src[ch], count: n)
                }
            }
            full.frameLength = AVAudioFrameCount(offset + n)
        }
        return full
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
