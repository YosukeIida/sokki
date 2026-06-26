import Testing
import AVFoundation
import SwiftData
@testable import SokkiKit

// MARK: - Helpers

private func make16kMonoFormat() -> AVAudioFormat {
    AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
}

/// `frameCount` フレームの無音バッファを作る。
private func makeSilentBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buf.frameLength = frameCount
    // floatChannelData[0] は 0 初期化済み（calloc）なので追加書き込み不要
    return buf
}

private func makeTmpURL(ext: String) -> URL {
    let dir = FileManager.default.temporaryDirectory
    return dir.appendingPathComponent("sokkiTest_\(UUID().uuidString).\(ext)")
}

// MARK: - AudioFileWriter Tests

@Suite("AudioFileWriter")
struct AudioFileWriterTests {

    @Test("WAV ラウンドトリップ: ファイルが存在し length > 0")
    func wavRoundTrip() throws {
        let format = make16kMonoFormat()
        let url = makeTmpURL(ext: "wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AudioFileWriter(url: url, processingFormat: format)

        // 16000 frames x 2 = 1 秒分
        let buf1 = makeSilentBuffer(format: format, frameCount: 16000)
        let buf2 = makeSilentBuffer(format: format, frameCount: 16000)
        writer.write(buf1)
        writer.write(buf2)
        writer.close()

        #expect(FileManager.default.fileExists(atPath: url.path))
        let readFile = try AVAudioFile(forReading: url)
        // PCM(WAV) は priming が無いため厳密一致で検証する。
        // length>0 だけだと書き込み欠落・二重書き込み・バッファとファイルの format 不一致
        // （例: 48kHz バッファを 16kHz ファイルへ）をすり抜けるため、frame 数・format を厳密確認。
        #expect(readFile.length == 32_000)
        #expect(readFile.processingFormat.sampleRate == 16_000)
        #expect(readFile.processingFormat.channelCount == 1)
    }

    @Test("close は冪等・close 後の write は無視される")
    func closeIsIdempotent() throws {
        let format = make16kMonoFormat()
        let url = makeTmpURL(ext: "wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AudioFileWriter(url: url, processingFormat: format)
        writer.write(makeSilentBuffer(format: format, frameCount: 16000))
        writer.close()
        writer.close()  // 二重 close でクラッシュしない
        writer.write(makeSilentBuffer(format: format, frameCount: 16000))  // close 後 write は no-op

        let readFile = try AVAudioFile(forReading: url)
        #expect(readFile.length == 16_000)  // close 後の write は反映されない
    }

    @Test("frameLength 0 のバッファは no-op")
    func zeroFrameBufferIsNoOp() throws {
        let format = make16kMonoFormat()
        let url = makeTmpURL(ext: "wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AudioFileWriter(url: url, processingFormat: format)
        writer.write(makeSilentBuffer(format: format, frameCount: 0))
        writer.write(makeSilentBuffer(format: format, frameCount: 8000))
        writer.close()

        let readFile = try AVAudioFile(forReading: url)
        #expect(readFile.length == 8_000)
    }

    @Test("M4A ラウンドトリップ: ファイルが存在し length > 0")
    func m4aRoundTrip() throws {
        let format = make16kMonoFormat()
        let url = makeTmpURL(ext: "m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AudioFileWriter(url: url, processingFormat: format)

        // AAC エンコーダは最低でも数百フレーム必要
        let buf = makeSilentBuffer(format: format, frameCount: 16000)
        writer.write(buf)
        writer.close()

        #expect(FileManager.default.fileExists(atPath: url.path))
        let readFile = try AVAudioFile(forReading: url)
        // AAC には priming frames があるため厳密一致はせず > 0 のみ確認
        #expect(readFile.length > 0)
    }
}

// MARK: - SessionManager Phase1 Tests

/// テスト用: SessionModel の Sendable な値だけを運ぶ構造体
struct SessionSnapshot: Sendable {
    let audioFilePath: String
    let durationSeconds: Double
}

extension SessionManager {
    /// テスト専用: 全セッションの Sendable スナップショットを返す。
    func allSessionSnapshots() throws -> [SessionSnapshot] {
        let descriptor = FetchDescriptor<SessionModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map {
            SessionSnapshot(audioFilePath: $0.audioFilePath, durationSeconds: $0.durationSeconds)
        }
    }
}

@Suite("SessionManager Phase1")
struct SessionManagerPhase1Tests {

    private func makeManager() throws -> SessionManager {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SessionModel.self,
                 SegmentModel.self,
                 SpeakerProfileModel.self,
                 AppSettingsModel.self,
            configurations: config
        )
        return SessionManager(modelContainer: container)
    }

    @Test("audioURL: 非 nil・m4a 拡張子・audioFilePath と一致")
    func audioURLMatchesFilePath() async throws {
        let manager = try makeManager()
        let sessionID = try await manager.createSession(title: "audioURLTest", mode: .micOnly)

        let url = await manager.audioURL(forSessionID: sessionID)
        #expect(url != nil)
        #expect(url?.pathExtension == "m4a")

        // audioFilePath との一致確認（actor 内で Sendable な値に変換）
        let snapshots = try await manager.allSessionSnapshots()
        let snap = try #require(snapshots.first)
        #expect(url?.path == snap.audioFilePath)
    }

    @Test("updateDuration: durationSeconds が正しく保存される")
    func updateDurationPersists() async throws {
        let manager = try makeManager()
        let sessionID = try await manager.createSession(title: "durationTest", mode: .micOnly)

        try await manager.updateDuration(sessionID: sessionID, duration: 12.5)

        let snapshots = try await manager.allSessionSnapshots()
        let snap = try #require(snapshots.first)
        #expect(snap.durationSeconds == 12.5)
    }

    @Test("結合: createSession の audioURL に AudioFileWriter で実際に書ける（P1-1 経路）")
    func writerWritesToSessionURL() async throws {
        let manager = try makeManager()
        let sessionID = try await manager.createSession(title: "integ", mode: .micOnly)
        let url = try #require(await manager.audioURL(forSessionID: sessionID))
        defer { try? FileManager.default.removeItem(at: url) }

        // SessionManager が払い出す実パス（Application Support 配下、ディレクトリ作成込み）に
        // AudioFileWriter で書けることを結合検証する。
        let format = make16kMonoFormat()
        let writer = try AudioFileWriter(url: url, processingFormat: format)
        writer.write(makeSilentBuffer(format: format, frameCount: 16000))
        writer.close()

        #expect(FileManager.default.fileExists(atPath: url.path))
        let readFile = try AVAudioFile(forReading: url)  // m4a: priming があるため > 0 で確認
        #expect(readFile.length > 0)
    }
}
