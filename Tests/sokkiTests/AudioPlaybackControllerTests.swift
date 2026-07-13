import Testing
import AVFoundation
import Foundation
@testable import SokkiKit

// MARK: - Helpers

/// 数百ms の無音 WAV を一時ディレクトリへ書き出し、URL を返す（音は出さず load→duration 検証に使う）。
private func makeSilentWavFile(seconds: Double = 0.5) throws -> URL {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sokkiTest_playback_\(UUID().uuidString).wav")

    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)

    let frameCount = AVAudioFrameCount(seconds * format.sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    try file.write(from: buffer)

    return url
}

// MARK: - AudioPlaybackController: セグメント同期の純粋関数

@Suite("AudioPlaybackController.segmentIndex")
struct AudioPlaybackControllerSegmentIndexTests {

    @Test("最初のセグメント開始前は nil")
    func beforeFirstSegmentIsNil() {
        let segments = [
            SegmentTimeRange(start: 1.0, end: 2.0),
            SegmentTimeRange(start: 3.0, end: 4.0),
        ]
        #expect(AudioPlaybackController.segmentIndex(at: 0.0, in: segments) == nil)
        #expect(AudioPlaybackController.segmentIndex(at: 0.999, in: segments) == nil)
    }

    @Test("セグメント区間内は該当 index")
    func withinSegmentReturnsIndex() {
        let segments = [
            SegmentTimeRange(start: 1.0, end: 2.0),
            SegmentTimeRange(start: 3.0, end: 4.0),
        ]
        #expect(AudioPlaybackController.segmentIndex(at: 1.0, in: segments) == 0)
        #expect(AudioPlaybackController.segmentIndex(at: 1.5, in: segments) == 0)
        #expect(AudioPlaybackController.segmentIndex(at: 3.5, in: segments) == 1)
    }

    @Test("セグメント間の無音区間は直前のセグメントを保持")
    func gapBetweenSegmentsKeepsPrevious() {
        let segments = [
            SegmentTimeRange(start: 1.0, end: 2.0),
            SegmentTimeRange(start: 3.0, end: 4.0),
        ]
        #expect(AudioPlaybackController.segmentIndex(at: 2.5, in: segments) == 0)
    }

    @Test("最後のセグメントの終了後も最後の index を保持")
    func afterLastSegmentKeepsLastIndex() {
        let segments = [
            SegmentTimeRange(start: 1.0, end: 2.0),
            SegmentTimeRange(start: 3.0, end: 4.0),
        ]
        #expect(AudioPlaybackController.segmentIndex(at: 100.0, in: segments) == 1)
    }

    @Test("空配列は常に nil")
    func emptySegmentsIsAlwaysNil() {
        #expect(AudioPlaybackController.segmentIndex(at: 0.0, in: []) == nil)
        #expect(AudioPlaybackController.segmentIndex(at: 100.0, in: []) == nil)
    }
}

// MARK: - AudioPlaybackController: ロード（合成 WAV・音出しなし）

@MainActor
@Suite("AudioPlaybackController.load")
struct AudioPlaybackControllerLoadTests {

    @Test("load: 実在する WAV ファイルで duration > 0 が取得できる")
    func loadValidWavSetsDuration() throws {
        let url = try makeSilentWavFile(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = AudioPlaybackController()
        controller.load(url: url)

        #expect(controller.playbackError == nil)
        #expect(controller.duration > 0)
        #expect(controller.currentTime == 0)
        #expect(controller.isPlaying == false)
    }

    @Test("load: 存在しないファイルは playbackError が設定され duration は 0")
    func loadMissingFileSetsError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sokkiTest_missing_\(UUID().uuidString).wav")

        let controller = AudioPlaybackController()
        controller.load(url: url)

        #expect(controller.playbackError != nil)
        #expect(controller.duration == 0)
    }

    @Test("seek: duration の範囲へクランプされる")
    func seekClampsToDuration() throws {
        let url = try makeSilentWavFile(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = AudioPlaybackController()
        controller.load(url: url)

        controller.seek(to: -10)
        #expect(controller.currentTime == 0)

        // 上限クランプの回帰チェック: `currentTime <= duration` だけだとシークが
        // 何もしなかった（0 のまま）場合も通ってしまうため、duration に実際に
        // 到達したことを許容誤差付きで確認する。
        controller.seek(to: 999)
        #expect(abs(controller.currentTime - controller.duration) < 0.05)
    }

    @Test("stop: 再生位置・duration・isPlaying がリセットされる")
    func stopResetsState() throws {
        let url = try makeSilentWavFile(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = AudioPlaybackController()
        controller.load(url: url)
        #expect(controller.duration > 0)

        controller.stop()

        #expect(controller.duration == 0)
        #expect(controller.currentTime == 0)
        #expect(controller.isPlaying == false)
    }
}

// MARK: - AudioPlaybackController: AVAudioPlayerDelegate

@MainActor
@Suite("AudioPlaybackController.delegate")
struct AudioPlaybackControllerDelegateTests {

    @Test("audioPlayerDidFinishPlaying: 正常終了(flag=true)で isPlaying=false・currentTime=duration になる")
    func finishSuccessfullyResetsToDuration() async throws {
        let url = try makeSilentWavFile(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = AudioPlaybackController()
        controller.load(url: url)
        controller.play()
        #expect(controller.isPlaying == true)

        let currentPlayer = try #require(controller.player)
        controller.audioPlayerDidFinishPlaying(currentPlayer, successfully: true)
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.isPlaying == false)
        #expect(controller.currentTime == controller.duration)
    }

    @Test("audioPlayerDidFinishPlaying: 異常終了(flag=false)では duration へスキップせず currentTime を反映する")
    func finishUnsuccessfullyKeepsActualPosition() async throws {
        let url = try makeSilentWavFile(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = AudioPlaybackController()
        controller.load(url: url)
        controller.play()
        let currentPlayer = try #require(controller.player)
        // 実際に再生が進行中のため、delegate 呼び出し「直前」の位置を基準値として
        // 保持する（呼び出し後に読み直すと再生がさらに進んでしまい誤検出になる）。
        let positionAtFinish = currentPlayer.currentTime

        controller.audioPlayerDidFinishPlaying(currentPlayer, successfully: false)
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.isPlaying == false)
        // flag=false のときは player.currentTime（実際に停止した位置）を反映し、
        // duration への強制ジャンプは起きない。
        #expect(abs(controller.currentTime - positionAtFinish) < 0.05)
    }

    @Test("audioPlayerDidFinishPlaying: 現在保持していない player からの通知は無視される（stale/foreign 通知対策）")
    func finishFromForeignPlayerIsIgnored() async throws {
        let url = try makeSilentWavFile(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = AudioPlaybackController()
        controller.load(url: url)
        controller.play()
        #expect(controller.isPlaying == true)

        // 現在保持しているインスタンスとは無関係な AVAudioPlayer からの通知。
        let foreignPlayer = try AVAudioPlayer(contentsOf: url)
        controller.audioPlayerDidFinishPlaying(foreignPlayer, successfully: true)
        try await Task.sleep(for: .milliseconds(100))

        // 無関係な player からの通知なので状態は変化しないはず。
        #expect(controller.isPlaying == true)

        controller.stop()
    }

    @Test("audioPlayerDecodeErrorDidOccur: isPlaying=false・playbackError が設定される（破損ファイル相当）")
    func decodeErrorUpdatesState() async throws {
        let url = try makeSilentWavFile(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = AudioPlaybackController()
        controller.load(url: url)
        controller.play()
        #expect(controller.isPlaying == true)

        struct DummyDecodeError: Error {}
        let currentPlayer = try #require(controller.player)
        controller.audioPlayerDecodeErrorDidOccur(currentPlayer, error: DummyDecodeError())
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.isPlaying == false)
        #expect(controller.playbackError != nil)
    }

    @Test("audioPlayerDecodeErrorDidOccur: 現在保持していない player からの通知は無視される")
    func decodeErrorFromForeignPlayerIsIgnored() async throws {
        let url = try makeSilentWavFile(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = AudioPlaybackController()
        controller.load(url: url)
        controller.play()
        #expect(controller.isPlaying == true)
        #expect(controller.playbackError == nil)

        struct DummyDecodeError: Error {}
        let foreignPlayer = try AVAudioPlayer(contentsOf: url)
        controller.audioPlayerDecodeErrorDidOccur(foreignPlayer, error: DummyDecodeError())
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.isPlaying == true)
        #expect(controller.playbackError == nil)

        controller.stop()
    }
}
