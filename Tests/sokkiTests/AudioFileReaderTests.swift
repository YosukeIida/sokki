import AVFoundation
import Foundation
import Testing
@testable import SokkiKit

/// TASK-25: AudioFileReader の復号・変換テスト。
/// 特に非 16kHz mono 入力の変換で、endOfStream による flush まで含めて
/// 期待サンプル数（時間長）が保たれることを検証する（レビュー指摘対応）。
@Suite("AudioFileReader")
struct AudioFileReaderTests {

    private func makeTempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-reader-test-\(UUID().uuidString).\(ext)")
    }

    /// 指定フォーマットで 1 秒分の sin 波を書き出す。
    private func writeSineFile(url: URL, sampleRate: Double, channels: AVAudioChannelCount) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
        let frames = AVAudioFrameCount(sampleRate)
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<Int(channels) {
            let p = buf.floatChannelData![ch]
            for i in 0..<Int(frames) {
                p[i] = sin(Float(i) * 0.02) * 0.5
            }
        }
        try file.write(from: buf)
        // deinit 任せでは書き込みが flush されないままテストが読みに行くことがある（実測で末尾欠落）。
        // macOS 15+ の close() で明示的に確定させる。
        file.close()
    }

    @Test("16kHz mono はそのまま読み出される")
    func readsNative16kMono() throws {
        let url = makeTempURL(ext: "wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineFile(url: url, sampleRate: 16_000, channels: 1)

        let samples = try AudioFileReader.readMonoSamples(url: url)
        #expect(samples.count == 16_000)
        #expect(samples.contains { abs($0) > 0.01 })
    }

    @Test("48kHz stereo が 16kHz mono へ末尾欠落なく変換される")
    func converts48kStereoTo16kMono() throws {
        let url = makeTempURL(ext: "wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineFile(url: url, sampleRate: 48_000, channels: 2)

        let samples = try AudioFileReader.readMonoSamples(url: url)
        // 1 秒の音声 → 16,000 サンプル。リサンプラの端数を許容しつつ、
        // endOfStream flush が無い場合の末尾欠落（数百サンプル規模）は検出できる誤差幅にする。
        #expect(abs(samples.count - 16_000) <= 64)
        #expect(samples.contains { abs($0) > 0.01 })
    }
}
