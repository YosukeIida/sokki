import AVFoundation
import Testing
@testable import SokkiKit

// SpeechAnalyzer 実文字起こし（モデルアセット DL を伴う）はテストしない。
// ここでは Speech フレームワークに依存しない純粋ロジックのみを検証する:
// - volatile / finalized → TranscriptionStreamUpdate の写像
// - [Float] → AVAudioPCMBuffer 生成とフォーマット変換
// - エンジン選択ロジック

@Suite("SpeechAnalyzerEngine")
struct SpeechAnalyzerEngineTests {

    // MARK: - volatile / finalized 写像

    @Test("確定結果は newlyConfirmed に載り hypothesis をクリアする")
    func finalResultBecomesConfirmed() {
        let update = speechAnalyzerStreamUpdate(
            isFinal: true, text: "  こんにちは  ", start: 1.0, end: 2.5)
        #expect(update.hypothesis == "")
        #expect(update.newlyConfirmed.count == 1)
        let seg = update.newlyConfirmed[0]
        #expect(seg.text == "こんにちは")   // 前後空白はトリムされる
        #expect(seg.start == 1.0)
        #expect(seg.end == 2.5)
        #expect(seg.isConfirmed)
    }

    @Test("空の確定結果は未確定テキストを消すだけ（確定セグメントは増やさない）")
    func emptyFinalClearsHypothesis() {
        let update = speechAnalyzerStreamUpdate(
            isFinal: true, text: "   ", start: 0, end: 1)
        #expect(update.newlyConfirmed.isEmpty)
        #expect(update.hypothesis == "")
    }

    @Test("暫定（volatile）結果は hypothesis をまるごと置換する")
    func volatileResultBecomesHypothesis() {
        let update = speechAnalyzerStreamUpdate(
            isFinal: false, text: " 途中経過 ", start: 0, end: 1)
        #expect(update.newlyConfirmed.isEmpty)
        #expect(update.hypothesis == "途中経過")
    }

    // MARK: - [Float] → AVAudioPCMBuffer

    @Test("makeSourceBuffer は 16kHz mono Float32 のバッファを作る")
    func makeSourceBufferProducesMonoFloat32() throws {
        let samples = [Float](repeating: 0.25, count: 320)
        let buffer = try #require(makeSourceBuffer(samples))
        #expect(buffer.format.sampleRate == 16_000)
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.format.commonFormat == .pcmFormatFloat32)
        #expect(buffer.frameLength == 320)
        #expect(buffer.floatChannelData?[0][0] == 0.25)
    }

    @Test("空配列からはバッファを作らない")
    func makeSourceBufferRejectsEmpty() {
        #expect(makeSourceBuffer([]) == nil)
    }

    // MARK: - フォーマット変換

    @Test("BufferConverter は同一フォーマットならそのまま返す")
    func converterPassesThroughIdenticalFormat() throws {
        let samples = [Float](repeating: 0.1, count: 160)
        let source = try #require(makeSourceBuffer(samples))
        let converter = BufferConverter()
        let out = try converter.convertBuffer(source, to: source.format)
        #expect(out.frameLength == 160)
        #expect(out.format.sampleRate == 16_000)
    }

    @Test("BufferConverter は 16kHz → 48kHz へリサンプルできる")
    func converterResamplesTo48k() throws {
        let samples = [Float](repeating: 0.1, count: 16_000)  // 1 秒
        let source = try #require(makeSourceBuffer(samples))
        let target = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let converter = BufferConverter()
        let out = try converter.convertBuffer(source, to: target)
        #expect(out.format.sampleRate == 48_000)
        #expect(out.format.channelCount == 1)
        // 1 秒ぶんなので 48k 近傍のフレーム数が得られる（リサンプラの端数を許容）。
        #expect(out.frameLength > 47_000)
        #expect(out.frameLength <= 48_000)
    }

    // MARK: - エンジン選択

    @Test("既定では WhisperKit エンジンを選ぶ")
    @MainActor
    func defaultEngineIsWhisperKit() {
        let engine = AppDependencyContainer.makeTranscriptionEngine(engineChoice: "whisperkit")
        #expect(engine is WhisperKitEngine)
    }

    @Test("未知の選択値でも WhisperKit にフォールバックする")
    @MainActor
    func unknownEngineFallsBackToWhisperKit() {
        let engine = AppDependencyContainer.makeTranscriptionEngine(engineChoice: "unknown")
        #expect(engine is WhisperKitEngine)
    }

    @Test("speechAnalyzer 選択時は対応 OS で SpeechAnalyzer エンジンを選ぶ")
    @MainActor
    func speechAnalyzerSelectedWhenAvailable() {
        let engine = AppDependencyContainer.makeTranscriptionEngine(engineChoice: "speechAnalyzer")
        if #available(macOS 26.0, *) {
            #expect(engine is SpeechAnalyzerEngine)
        } else {
            #expect(engine is WhisperKitEngine)
        }
    }
}
