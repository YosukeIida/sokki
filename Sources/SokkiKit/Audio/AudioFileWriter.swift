import AVFoundation

/// 録音音声をディスクへ書き出す（P1-1）。
///
/// 音声スレッド（`installTap` コールバック）から `write(_:)` が同期的に呼ばれ、
/// アクター（`AudioCaptureManager`）の `stopCapture` から `close()` が呼ばれる。
/// 両者の競合を `NSLock` で直列化するため `@unchecked Sendable`。
///
/// 拡張子で出力形式を選ぶ: `.wav` は PCM 16bit、それ以外は AAC（`.m4a`）。
/// 入力バッファは 16kHz mono Float32（`AudioCaptureManager` の targetFormat）を想定し、
/// `AVAudioFile` が on-disk 形式へエンコードする。
final class AudioFileWriter: @unchecked Sendable {

    private let lock = NSLock()
    private var file: AVAudioFile?
    private var _lastWriteError: Error?

    /// 直近の書き込み失敗（容量不足など）。呼び出し元がポーリングして利用者へ通知するために使う。
    var lastWriteError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return _lastWriteError
    }

    init(url: URL, processingFormat: AVAudioFormat) throws {
        let settings: [String: Any]
        if url.pathExtension.lowercased() == "wav" {
            settings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: processingFormat.sampleRate,
                AVNumberOfChannelsKey: processingFormat.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        } else {
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: processingFormat.sampleRate,
                AVNumberOfChannelsKey: processingFormat.channelCount,
            ]
        }
        // commonFormat / interleaved は write(from:) に渡すバッファの形式に一致させる。
        file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }

    /// 音声スレッドから同期的に呼ばれる。書き込みは録音継続を優先して止めないが、
    /// エラーは `lastWriteError` に記録し、呼び出し元が利用者へ通知できるようにする（P1）。
    func write(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }
        do {
            try file.write(from: buffer)
        } catch {
            _lastWriteError = error
        }
    }

    /// 解放時にファイルがファイナライズされる。冪等。
    func close() {
        lock.lock()
        defer { lock.unlock() }
        file = nil
    }
}
