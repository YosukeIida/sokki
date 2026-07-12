import Testing
import Foundation
import AVFoundation
@testable import SokkiKit

// MARK: - Shared ordering log

/// mic / system の起動・停止順序を検証するための共有ログ。2 つのモックが同じインスタンスへ
/// 追記し、`AudioCaptureManager` が呼び出した順序を厳密に確認する。
final class CaptureCallLog: @unchecked Sendable {
    enum Event: Equatable {
        case systemStart, micStart, systemStop, micStop
    }
    private let lock = NSLock()
    private var _events: [Event] = []
    var events: [Event] { lock.lock(); defer { lock.unlock() }; return _events }
    func record(_ event: Event) { lock.lock(); _events.append(event); lock.unlock() }
}

// MARK: - Mock microphone

/// `MicrophoneCapturing` のモック。`AVAudioEngine` に触れず、`send` で任意の `[Float]` を注入できる。
/// `SystemAudioTapping` のモック（`MockSystemAudioTap`）と対称。
final class MockMicrophoneCapture: MicrophoneCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var onSamples: (@Sendable ([Float], Date) -> Void)?
    private var _startCount = 0
    private var _stopCount = 0
    private var _shouldFail = false
    private let callLog: CaptureCallLog?

    init(log: CaptureCallLog? = nil) {
        self.callLog = log
    }

    var startCount: Int { lock.lock(); defer { lock.unlock() }; return _startCount }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return _stopCount }

    /// 次回 `start` を失敗させる（Both 起動中の mic 失敗と巻き戻しを再現）。
    func setShouldFail(_ shouldFail: Bool) {
        lock.lock(); defer { lock.unlock() }
        _shouldFail = shouldFail
    }

    func start(onSamples: @escaping @Sendable ([Float], Date) -> Void) throws {
        lock.lock()
        let shouldFail = _shouldFail
        if !shouldFail {
            self.onSamples = onSamples
            _startCount += 1
            callLog?.record(.micStart)
        }
        lock.unlock()
        if shouldFail { throw MicrophoneCaptureError.converterUnavailable }
    }

    func stop() {
        lock.lock()
        onSamples = nil
        _stopCount += 1
        callLog?.record(.micStop)
        lock.unlock()
    }

    /// テストからサンプルを注入する（音声スレッド相当・同期実行）。
    func send(_ samples: [Float], at date: Date = Date()) {
        lock.lock()
        let callback = onSamples
        lock.unlock()
        callback?(samples, date)
    }
}

// MARK: - Helpers

private func makeTmpURL(ext: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("sokkiBothTest_\(UUID().uuidString).\(ext)")
}

private func makeChunk(_ lane: AudioLane) -> AudioChunk {
    AudioChunk(lane: lane, samples: [0.1, 0.2, 0.3], capturedAt: Date())
}

// MARK: - Both mode lifecycle

@Suite("AudioCaptureManager Both mode")
struct BothModeCaptureTests {

    @Test("起動順は system 先 → mic 後")
    func startsSystemBeforeMic() async throws {
        let log = CaptureCallLog()
        let systemMock = MockSystemAudioTap(log: log)
        let micMock = MockMicrophoneCapture(log: log)
        let manager = AudioCaptureManager(systemTap: systemMock, microphone: micMock)

        try await manager.startCapture(mode: .both)

        #expect(log.events == [.systemStart, .micStart])
        #expect(systemMock.startCount == 1)
        #expect(micMock.startCount == 1)

        await manager.stopCapture()
    }

    @Test("停止は逆順: mic 先 → system 後")
    func stopsMicBeforeSystem() async throws {
        let log = CaptureCallLog()
        let systemMock = MockSystemAudioTap(log: log)
        let micMock = MockMicrophoneCapture(log: log)
        let manager = AudioCaptureManager(systemTap: systemMock, microphone: micMock)

        try await manager.startCapture(mode: .both)
        await manager.stopCapture()

        #expect(log.events == [.systemStart, .micStart, .micStop, .systemStop])
    }

    @Test("巻き戻し: mic 起動失敗時は起動済み system を停止して throw する")
    func rollsBackSystemWhenMicFails() async throws {
        let log = CaptureCallLog()
        let systemMock = MockSystemAudioTap(log: log)
        let micMock = MockMicrophoneCapture(log: log)
        micMock.setShouldFail(true)
        let manager = AudioCaptureManager(systemTap: systemMock, microphone: micMock)

        await #expect(throws: AudioCaptureManager.CaptureError.self) {
            try await manager.startCapture(mode: .both)
        }

        // system は起動 → 巻き戻しで停止。mic は起動していない。
        #expect(systemMock.startCount == 1)
        #expect(systemMock.stopCount == 1)
        #expect(micMock.startCount == 0)
        #expect(log.events == [.systemStart, .systemStop])
    }

    @Test("両レーンの level ストリームが両立して流れる")
    func bothLevelStreamsFlow() async throws {
        let systemMock = MockSystemAudioTap()
        let micMock = MockMicrophoneCapture()
        let manager = AudioCaptureManager(systemTap: systemMock, microphone: micMock)

        try await manager.startCapture(mode: .both)
        let micLevels = await manager.micLevelStream
        let systemLevels = await manager.systemLevelStream

        micMock.send(Array(repeating: 0.4, count: 160))
        systemMock.send(Array(repeating: 0.3, count: 160))

        var micIterator = micLevels.makeAsyncIterator()
        let micLevel = try #require(await micIterator.next())
        #expect(micLevel > -60)

        var systemIterator = systemLevels.makeAsyncIterator()
        let systemLevel = try #require(await systemIterator.next())
        #expect(systemLevel > -60)

        await manager.stopCapture()
    }

    @Test("2 ファイル別保存: mic と system が別ファイルに別内容で書かれる")
    func writesTwoSeparateFiles() async throws {
        let systemMock = MockSystemAudioTap()
        let micMock = MockMicrophoneCapture()
        let manager = AudioCaptureManager(systemTap: systemMock, microphone: micMock)

        // 決定的に長さを検証するため WAV（PCM）を使う。
        let primaryURL = makeTmpURL(ext: "wav")
        let systemURL = AudioCaptureManager.systemFileURL(forPrimary: primaryURL)
        defer {
            try? FileManager.default.removeItem(at: primaryURL)
            try? FileManager.default.removeItem(at: systemURL)
        }

        try await manager.startCapture(mode: .both, outputURL: primaryURL)

        // mic と system で明確に異なるフレーム数を書き、ファイル内容が異なることを保証する。
        micMock.send(Array(repeating: 0.5, count: 16_000))     // 1.0 秒
        systemMock.send(Array(repeating: 0.2, count: 8_000))   // 0.5 秒

        await manager.stopCapture()

        #expect(FileManager.default.fileExists(atPath: primaryURL.path))
        #expect(FileManager.default.fileExists(atPath: systemURL.path))

        let micFile = try AVAudioFile(forReading: primaryURL)
        let systemFile = try AVAudioFile(forReading: systemURL)
        #expect(micFile.length == 16_000)
        #expect(systemFile.length == 8_000)
        #expect(micFile.length != systemFile.length)
    }

    @Test("systemFileURL: 拡張子直前に _system を挿入する")
    func systemFileURLDerivation() {
        let primary = URL(fileURLWithPath: "/tmp/rec/session_ab12.m4a")
        let derived = AudioCaptureManager.systemFileURL(forPrimary: primary)
        #expect(derived.lastPathComponent == "session_ab12_system.m4a")
        #expect(derived.deletingLastPathComponent().path == primary.deletingLastPathComponent().path)
    }
}

// MARK: - Stream merge

@Suite("mergeAudioStreams")
struct AudioStreamMergeTests {

    @Test("両入力のチャンクを 1 本に合成し、両方が finish したら finish する")
    func mergesBothLanes() async {
        var micCont: AsyncStream<AudioChunk>.Continuation!
        var systemCont: AsyncStream<AudioChunk>.Continuation!
        let micStream = AsyncStream<AudioChunk> { micCont = $0 }
        let systemStream = AsyncStream<AudioChunk> { systemCont = $0 }

        let merged = mergeAudioStreams(micStream, systemStream)

        micCont.yield(makeChunk(.microphone))
        systemCont.yield(makeChunk(.system))
        micCont.yield(makeChunk(.microphone))
        micCont.finish()
        systemCont.finish()

        var lanes: [AudioLane] = []
        for await chunk in merged { lanes.append(chunk.lane) }

        // 到着順序はタスクスケジューリングに依存するため、件数と両レーンの存在を検証する。
        #expect(lanes.count == 3)
        #expect(lanes.contains(.microphone))
        #expect(lanes.contains(.system))
    }

    @Test("片方だけ finish しても、もう片方が続く限り合成ストリームは finish しない")
    func doesNotFinishUntilBothFinish() async throws {
        var micCont: AsyncStream<AudioChunk>.Continuation!
        var systemCont: AsyncStream<AudioChunk>.Continuation!
        let micStream = AsyncStream<AudioChunk> { micCont = $0 }
        let systemStream = AsyncStream<AudioChunk> { systemCont = $0 }

        let merged = mergeAudioStreams(micStream, systemStream)
        var iterator = merged.makeAsyncIterator()

        micCont.finish()                       // mic だけ先に終了
        systemCont.yield(makeChunk(.system))   // system はまだ流れる

        let chunk = await iterator.next()
        #expect(chunk?.lane == .system)

        systemCont.finish()
        let end = await iterator.next()
        #expect(end == nil)                    // 両方終了で合成ストリームも終了
    }
}
