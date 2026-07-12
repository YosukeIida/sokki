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

        controller.seek(to: 999)
        #expect(controller.currentTime <= controller.duration)
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
