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
    /// Both モードの起動／停止順序を検証するための共有ログ（任意）。
    private let callLog: CaptureCallLog?

    init(log: CaptureCallLog? = nil) {
        self.callLog = log
    }

    var startCount: Int { lock.lock(); defer { lock.unlock() }; return _startCount }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return _stopCount }

    /// 現在保持している yield クロージャ（旧世代の混入テストで退避に使う）。
    var capturedOnSamples: (@Sendable ([Float], Date) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return onSamples
    }

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
            callLog?.record(.systemStart)
        }
        lock.unlock()
        if let error { throw error }
    }

    func stop() {
        lock.lock()
        onSamples = nil
        _stopCount += 1
        callLog?.record(.systemStop)
        lock.unlock()
    }

    /// テストからサンプルを注入する（実装の IO キュー相当）。
    func send(_ samples: [Float], at date: Date = Date()) {
        lock.lock()
        let callback = onSamples
        lock.unlock()
        callback?(samples, date)
    }
}

/// `CoreAudioTapSystem` のフェイク。呼び出し順序を記録し、任意の段階で失敗させられる。
/// Core Audio 実機に触れずに `SystemAudioTap` の生成／解放シーケンスを検証する。
final class FakeCoreAudioTapSystem: CoreAudioTapSystem, @unchecked Sendable {

    enum Call: Equatable {
        case createProcessTap
        case defaultOutputUID
        case tapStreamFormat
        case createAggregateDevice
        case createIOProcID
        case startDevice
        case stopDevice
        case destroyIOProcID
        case destroyAggregateDevice
        case destroyProcessTap
    }

    static let failStatus: OSStatus = -99
    /// 破棄系呼び出しだけを抽出するためのフィルタ集合。
    static let teardownCalls: Set<Call> = [
        .stopDevice, .destroyIOProcID, .destroyAggregateDevice, .destroyProcessTap,
    ]
    /// C 関数ポインタへ変換できる非キャプチャの sentinel proc ID。
    static let sentinelProcID: AudioDeviceIOProcID = { _, _, _, _, _, _, _ in noErr }

    private let failAt: Call?
    private let lock = NSLock()
    private var _calls: [Call] = []

    init(failAt: Call? = nil) {
        self.failAt = failAt
    }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    var teardownSequence: [Call] { calls.filter { Self.teardownCalls.contains($0) } }

    private func record(_ call: Call) {
        lock.lock(); _calls.append(call); lock.unlock()
    }

    func createProcessTap(_ description: CATapDescription) -> (status: OSStatus, tapID: AudioObjectID) {
        record(.createProcessTap)
        return failAt == .createProcessTap
            ? (Self.failStatus, AudioObjectID(kAudioObjectUnknown))
            : (noErr, 100)
    }

    func defaultSystemOutputDeviceUID() -> (status: OSStatus, uid: String?) {
        record(.defaultOutputUID)
        return failAt == .defaultOutputUID ? (Self.failStatus, nil) : (noErr, "FakeOutputUID")
    }

    func tapStreamFormat(tapID: AudioObjectID) -> (status: OSStatus, format: AVAudioFormat?) {
        record(.tapStreamFormat)
        if failAt == .tapStreamFormat { return (Self.failStatus, nil) }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false
        )!
        return (noErr, format)
    }

    func createAggregateDevice(_ description: CFDictionary) -> (status: OSStatus, deviceID: AudioObjectID) {
        record(.createAggregateDevice)
        return failAt == .createAggregateDevice
            ? (Self.failStatus, AudioObjectID(kAudioObjectUnknown))
            : (noErr, 200)
    }

    func createIOProcID(
        deviceID: AudioObjectID,
        queue: DispatchQueue,
        ioBlock: @escaping AudioDeviceIOBlock
    ) -> (status: OSStatus, procID: AudioDeviceIOProcID?) {
        record(.createIOProcID)
        return failAt == .createIOProcID ? (Self.failStatus, nil) : (noErr, Self.sentinelProcID)
    }

    func startDevice(deviceID: AudioObjectID, procID: AudioDeviceIOProcID) -> OSStatus {
        record(.startDevice)
        return failAt == .startDevice ? Self.failStatus : noErr
    }

    func stopDevice(deviceID: AudioObjectID, procID: AudioDeviceIOProcID) { record(.stopDevice) }
    func destroyIOProcID(deviceID: AudioObjectID, procID: AudioDeviceIOProcID) { record(.destroyIOProcID) }
    func destroyAggregateDevice(deviceID: AudioObjectID) { record(.destroyAggregateDevice) }
    func destroyProcessTap(tapID: AudioObjectID) { record(.destroyProcessTap) }
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

    @Test("回帰: 停止後に遅延実行された旧世代の chunk は新 systemStream に混入しない")
    func staleGenerationChunkIsDiscarded() async throws {
        let mock = MockSystemAudioTap()
        let manager = AudioCaptureManager(systemTap: mock)

        // セッション1を開始し、その世代の yield クロージャを退避する。
        try await manager.startCapture(mode: .systemOnly)
        let staleClosure = try #require(mock.capturedOnSamples)
        await manager.stopCapture()

        // セッション2を開始（新しい世代・新しい systemStream）。
        try await manager.startCapture(mode: .systemOnly)
        let stream = await manager.systemStream

        // 旧世代クロージャで chunk を流し込む（AudioDeviceStop 後に遅延実行された IO Task を再現）。
        staleClosure(Array(repeating: 0.9, count: 99), Date())
        // 現行世代の chunk を流す（判別のためサンプル数を変える）。
        mock.send(Array(repeating: 0.1, count: 3))

        var iterator = stream.makeAsyncIterator()
        let chunk = await iterator.next()
        // 最初に届く chunk は現行世代（count == 3）でなければならない。旧世代（99）は破棄される。
        #expect(chunk?.samples.count == 3)

        await manager.stopCapture()
    }
}

// MARK: - SystemAudioTap lifecycle (injected Core Audio fake)

@Suite("SystemAudioTap lifecycle")
struct SystemAudioTapLifecycleTests {

    @Test("正常 stop は Stop→DestroyIOProcID→DestroyAggregateDevice→DestroyProcessTap の順で解放する")
    func teardownInReverseOrder() throws {
        let fake = FakeCoreAudioTapSystem()
        let tap = SystemAudioTap(coreAudio: fake)

        try tap.start { _, _ in }
        tap.stop()

        #expect(fake.teardownSequence == [
            .stopDevice, .destroyIOProcID, .destroyAggregateDevice, .destroyProcessTap,
        ])
    }

    @Test("二重 start は alreadyStarted を throw し、既存リソースを再生成しない")
    func doubleStartThrows() throws {
        let fake = FakeCoreAudioTapSystem()
        let tap = SystemAudioTap(coreAudio: fake)

        try tap.start { _, _ in }
        #expect(throws: SystemAudioTapError.alreadyStarted) {
            try tap.start { _, _ in }
        }
        // 2 回目は guard で弾かれ Core Audio に一切触れない。
        #expect(fake.calls.filter { $0 == .createProcessTap }.count == 1)

        tap.stop()
    }

    @Test("aggregate 生成失敗時は生成済み tap のみを解放して throw する")
    func rollbackOnAggregateFailure() {
        let fake = FakeCoreAudioTapSystem(failAt: .createAggregateDevice)
        let tap = SystemAudioTap(coreAudio: fake)

        #expect(throws: SystemAudioTapError.aggregateDeviceCreationFailed(FakeCoreAudioTapSystem.failStatus)) {
            try tap.start { _, _ in }
        }
        // process tap のみ生成済み → destroyProcessTap だけが呼ばれる。
        #expect(fake.teardownSequence == [.destroyProcessTap])
    }

    @Test("開始失敗時は IOProc→AggregateDevice→ProcessTap の順で解放する（Stop は呼ばない）")
    func rollbackOnStartFailure() {
        let fake = FakeCoreAudioTapSystem(failAt: .startDevice)
        let tap = SystemAudioTap(coreAudio: fake)

        #expect(throws: SystemAudioTapError.deviceStartFailed(FakeCoreAudioTapSystem.failStatus)) {
            try tap.start { _, _ in }
        }
        // 未起動なので Stop は呼ばず、生成済みリソースを逆順に破棄する。
        #expect(fake.teardownSequence == [
            .destroyIOProcID, .destroyAggregateDevice, .destroyProcessTap,
        ])
    }
}
