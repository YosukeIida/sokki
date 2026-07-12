import Testing
import Foundation
import AVFoundation
import CoreAudio
@testable import SokkiKit

// MARK: - Mock

/// `SystemAudioTapping` のモック。Core Audio に触れず、テストから `send` で任意の
/// `[Float]` を注入できる。`onSamples` は実装同様に呼び出しスレッド上で同期実行される。
final class MockSystemAudioTap: SystemAudioTapping, @unchecked Sendable {
    private let lock = NSLock()
    private var onSamples: (@Sendable ([Float], Date) -> Void)?
    private var _startCount = 0
    private var _stopCount = 0
    private var _errorToThrow: SystemAudioTapError?

    var startCount: Int { lock.lock(); defer { lock.unlock() }; return _startCount }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return _stopCount }

    func setError(_ error: SystemAudioTapError?) {
        lock.lock(); defer { lock.unlock() }
        _errorToThrow = error
    }

    func start(onSamples: @escaping @Sendable ([Float], Date) -> Void) throws {
        lock.lock()
        let error = _errorToThrow
        if error == nil {
            self.onSamples = onSamples
            _startCount += 1
        }
        lock.unlock()
        if let error { throw error }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        onSamples = nil
        _stopCount += 1
    }

    /// テストからサンプルを注入する（実装の IO キュー相当）。
    func send(_ samples: [Float], at date: Date = Date()) {
        lock.lock()
        let callback = onSamples
        lock.unlock()
        callback?(samples, date)
    }
}

// MARK: - Aggregate device description builder

@Suite("SystemAudioTap aggregate device description")
struct AggregateDeviceDescriptionTests {

    @Test("必須キー: UUID 文字列・TapAutoStart・IsPrivate・両 UID キーが揃う")
    func containsRequiredKeys() {
        let tapUUID = UUID()
        let outputUID = "BuiltInSpeakerDevice"
        let dict = SystemAudioTap.makeAggregateDeviceDescription(
            tapUUID: tapUUID,
            outputDeviceUID: outputUID,
            aggregateUID: "sokki-agg-test"
        )

        // TapAutoStart / IsPrivate
        #expect(dict[kAudioAggregateDeviceTapAutoStartKey as String] as? Bool == true)
        #expect(dict[kAudioAggregateDeviceIsPrivateKey as String] as? Bool == true)

        // 出力 UID は MainSubDevice と SubDeviceList[0] の両方
        #expect(dict[kAudioAggregateDeviceMainSubDeviceKey as String] as? String == outputUID)
        let subList = dict[kAudioAggregateDeviceSubDeviceListKey as String] as? [[String: Any]]
        #expect(subList?.count == 1)
        #expect(subList?.first?[kAudioSubDeviceUIDKey as String] as? String == outputUID)

        // TapList には tap の UUID 文字列（tapID 整数ではない）と drift 補償
        let tapList = dict[kAudioAggregateDeviceTapListKey as String] as? [[String: Any]]
        #expect(tapList?.count == 1)
        #expect(tapList?.first?[kAudioSubTapUIDKey as String] as? String == tapUUID.uuidString)
        #expect(tapList?.first?[kAudioSubTapDriftCompensationKey as String] as? Bool == true)
    }
}

// MARK: - Sample conversion

@Suite("AudioSampleConversion")
struct AudioSampleConversionTests {

    @Test("48kHz stereo → 16kHz mono 変換の出力を検証")
    func convertsStereo48kToMono16k() throws {
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false
        )!
        let targetFormat = AudioSampleConversion.makeTargetFormat()
        let converter = try #require(AVAudioConverter(from: inputFormat, to: targetFormat))

        let frames: AVAudioFrameCount = 4_800   // 0.1 秒
        let inBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames)!
        inBuffer.frameLength = frames
        // 両チャンネルに 0.5 振幅の正弦波を書く（無音でないことを保証）。
        for channel in 0..<2 {
            let pointer = inBuffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                pointer[i] = sin(Float(i) * 0.05) * 0.5
            }
        }

        let outBuffer = try #require(
            AudioSampleConversion.convertToBuffer(inBuffer, using: converter, to: targetFormat)
        )
        #expect(outBuffer.format.sampleRate == 16_000)
        #expect(outBuffer.format.channelCount == 1)

        let samples = AudioSampleConversion.samples(from: outBuffer)
        // 48k→16k で約 1/3 のフレーム数（4800→1600）。リサンプラの端数を許容して幅で検証。
        #expect(samples.count > 1_000)
        #expect(samples.count <= 1_600)

        // レベルは dBFS RMS の範囲内で、無音（-60）より大きい。
        let level = AudioSampleConversion.rmsLevel(samples)
        #expect(level > -60)
        #expect(level <= 0)
    }

    @Test("空配列・無音の RMS は -60")
    func silenceLevelIsFloor() {
        #expect(AudioSampleConversion.rmsLevel([]) == -60)
        #expect(AudioSampleConversion.rmsLevel([0, 0, 0, 0]) == -60)
    }
}

// MARK: - AudioCaptureManager system audio wiring

@Suite("AudioCaptureManager system audio")
struct SystemAudioCaptureTests {

    @Test("startCapture(.systemOnly) は throw せず chunk / レベルが両ストリームに流れる")
    func systemOnlyStreamsChunksAndLevels() async throws {
        let mock = MockSystemAudioTap()
        let manager = AudioCaptureManager(systemTap: mock)

        try await manager.startCapture(mode: .systemOnly)
        #expect(mock.startCount == 1)

        let stream = await manager.systemStream
        let levelStream = await manager.systemLevelStream

        let payload: [Float] = Array(repeating: 0.4, count: 160)
        mock.send(payload)

        var chunkIterator = stream.makeAsyncIterator()
        let chunk = await chunkIterator.next()
        #expect(chunk?.lane == .system)
        #expect(chunk?.samples.count == 160)

        var levelIterator = levelStream.makeAsyncIterator()
        let level = await levelIterator.next()
        let unwrappedLevel = try #require(level)
        #expect(unwrappedLevel > -60)
        #expect(unwrappedLevel <= 0)

        await manager.stopCapture()
    }

    @Test("stopCapture() で systemStream / systemLevelStream が finish する")
    func stopCaptureFinishesSystemStreams() async throws {
        let mock = MockSystemAudioTap()
        let manager = AudioCaptureManager(systemTap: mock)

        try await manager.startCapture(mode: .systemOnly)
        let stream = await manager.systemStream
        let levelStream = await manager.systemLevelStream

        await manager.stopCapture()
        #expect(mock.stopCount == 1)

        var chunkCount = 0
        for await _ in stream { chunkCount += 1 }
        #expect(chunkCount == 0)

        var levelCount = 0
        for await _ in levelStream { levelCount += 1 }
        #expect(levelCount == 0)
    }

    @Test("2 回目の録音でも再購読できる")
    func systemCaptureCanBeRestarted() async throws {
        let mock = MockSystemAudioTap()
        let manager = AudioCaptureManager(systemTap: mock)

        try await manager.startCapture(mode: .systemOnly)
        await manager.stopCapture()

        try await manager.startCapture(mode: .systemOnly)
        #expect(mock.startCount == 2)

        let stream = await manager.systemStream
        mock.send([0.2, 0.3, 0.4])

        var iterator = stream.makeAsyncIterator()
        let chunk = await iterator.next()
        #expect(chunk?.lane == .system)
        #expect(chunk?.samples.count == 3)

        await manager.stopCapture()
    }

    @Test("回帰: .both は引き続き明確なエラーを throw する")
    func bothModeStillThrows() async {
        let manager = AudioCaptureManager(systemTap: MockSystemAudioTap())
        await #expect(throws: AudioCaptureManager.CaptureError.self) {
            try await manager.startCapture(mode: .both)
        }
    }
}
