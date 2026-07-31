import AVFoundation

/// マイク音声キャプチャ（AVAudioEngine / Phase 1）の生成失敗を表すエラー。
enum MicrophoneCaptureError: Error {
    /// 入力フォーマット → 16kHz mono への変換器を生成できなかった。
    case converterUnavailable
    /// `AVAudioEngine.start()` が失敗した。基底エラーを保持する。
    case engineStartFailed(Error)
}

/// マイク音声キャプチャの抽象。実装（`MicrophoneCapture`）は `AVAudioEngine` を、
/// テストはモックを注入する。`SystemAudioTapping` と同じシグネチャ（16kHz mono の `[Float]` と
/// キャプチャ時刻を渡す）に揃え、`AudioCaptureManager` が両レーンを対称に扱えるようにする。
protocol MicrophoneCapturing: Sendable {
    /// キャプチャを開始する。`onSamples` は音声スレッド（`installTap` コールバック）から
    /// 同期的に呼ばれ、16kHz mono に変換済みの `[Float]` を渡す。
    func start(onSamples: @escaping @Sendable ([Float], Date) -> Void) throws
    /// キャプチャを停止し、エンジン・tap を解放する。冪等。
    func stop()
}

/// `AVAudioEngine` によるマイク音声キャプチャの実装。
///
/// 入力ノードをネイティブフォーマットでタップし、`AudioSampleConversion` で 16kHz mono Float32 に
/// 変換して `onSamples` へ渡す。ファイル書き出しは呼び出し元（`AudioCaptureManager`）が担うため、
/// ここでは変換済み `[Float]` を渡すだけに責務を絞る（システム側 `SystemAudioTap` と対称）。
///
/// `start` / `stop` はアクターから直列に呼ばれるが、`@unchecked Sendable` を honest に満たすため
/// エンジンハンドルを `NSLock` で保護する。
final class MicrophoneCapture: MicrophoneCapturing, @unchecked Sendable {

    private let lock = NSLock()
    private var engine: AVAudioEngine?

    init() {}

    deinit {
        stop()
    }

    func start(onSamples: @escaping @Sendable ([Float], Date) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        // 二重 start は無視する（呼び出し側は stop してから start する契約）。
        guard engine == nil else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AudioSampleConversion.makeTargetFormat()

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw MicrophoneCaptureError.converterUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let outBuffer = AudioSampleConversion.convertToBuffer(
                buffer, using: converter, to: targetFormat
            ) else { return }
            let samples = AudioSampleConversion.samples(from: outBuffer)
            guard !samples.isEmpty else { return }
            onSamples(samples, Date())
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw MicrophoneCaptureError.engineStartFailed(error)
        }
        self.engine = engine
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }
}
