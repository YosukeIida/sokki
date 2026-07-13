import AVFoundation
import SwiftData
import Testing
@testable import SokkiKit

// テスト用ヘルパー（MockTranscriptionEngineTests.swift の setShouldThrowOnPrepare 等と同じ方針）
extension MockTranscriptionEngine {
    func setStubbedSegments(to segments: [any TranscriptionSegment]) {
        stubbedSegments = segments
    }

    func setShouldThrowOnTranscribe(_ value: Bool) {
        shouldThrowOnTranscribe = value
    }
}

/// TASK-34 / P4-3: ファイルインポート（.mp4/.m4a/.wav/.mp3）の結合テスト。
/// 合成 WAV を実際にディスクへ書き出し、`AudioFileImporter` 経由でセッション作成〜
/// 文字起こし〜diarization までの一連のバッチ処理を検証する。
@Suite("AudioFileImporter")
@MainActor
struct AudioFileImporterTests {

    // MARK: - Fixtures

    private func make16kMonoFormat() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    }

    private func makeSilentBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buf.frameLength = frameCount
        return buf
    }

    private func makeTmpURL(name: String = UUID().uuidString, ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
    }

    /// `frameCount` フレーム分の無音 WAV ファイルを作る（0 を渡すと空ファイルになる）。
    private func makeWavFile(frameCount: AVAudioFrameCount, ext: String = "wav") throws -> URL {
        let format = make16kMonoFormat()
        let url = makeTmpURL(ext: ext)
        let writer = try AudioFileWriter(url: url, processingFormat: format)
        if frameCount > 0 {
            writer.write(makeSilentBuffer(format: format, frameCount: frameCount))
        }
        writer.close()
        return url
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: SessionModel.self, SegmentModel.self, SpeakerProfileModel.self, AppSettingsModel.self,
            configurations: config
        )
    }

    private func makeImporter(
        container: ModelContainer,
        transcription: MockTranscriptionEngine = MockTranscriptionEngine(),
        diarization: MockDiarizationEngine = MockDiarizationEngine()
    ) -> (importer: AudioFileImporter, sessionManager: SessionManager) {
        let sessionManager = SessionManager(modelContainer: container)
        let store = SpeakerProfileStore(modelContext: ModelContext(container))
        let pipeline = TranscriptionPipeline(
            captureManager: AudioCaptureManager(),
            transcriptionEngine: transcription,
            diarizationEngine: diarization,
            speakerStore: store,
            sessionManager: sessionManager
        )
        let importer = AudioFileImporter(
            transcriptionEngine: transcription,
            sessionManager: sessionManager,
            pipeline: pipeline
        )
        return (importer, sessionManager)
    }

    private func fetchSessions(_ container: ModelContainer) throws -> [SessionModel] {
        let ctx = ModelContext(container)
        return try ctx.fetch(FetchDescriptor<SessionModel>())
    }

    private func makeResult(
        _ specs: [(speakerID: String, start: Double, end: Double, embedding: [Float])]
    ) -> DiarizationResult {
        let segments = specs.map {
            DiarizationSegment(start: $0.start, end: $0.end, speakerID: $0.speakerID, embedding: $0.embedding)
        }
        return DiarizationResult(
            segments: segments,
            numberOfSpeakers: Set(specs.map { $0.speakerID }).count
        )
    }

    // MARK: - 形式判定

    @Test("対応拡張子は mp4/m4a/wav/mp3（大小文字を無視）")
    func supportedExtensionsMatchSpec() {
        #expect(AudioFileImporter.supportedExtensions == ["mp4", "m4a", "wav", "mp3"])
    }

    @Test("非対応形式はセッションを作らずエラーになる")
    func rejectsUnsupportedFormat() async throws {
        let container = try makeContainer()
        let (importer, sessionManager) = makeImporter(container: container)

        let fakeURL = FileManager.default.temporaryDirectory.appendingPathComponent("clip.mov")
        await importer.importFile(at: fakeURL)

        #expect(importer.importErrorMessage != nil)
        let count = try await sessionManager.sessionCount()
        #expect(count == 0)
    }

    @Test("拡張子なしのファイルもエラーになる")
    func rejectsExtensionlessFile() async throws {
        let container = try makeContainer()
        let (importer, sessionManager) = makeImporter(container: container)

        let fakeURL = FileManager.default.temporaryDirectory.appendingPathComponent("noext")
        await importer.importFile(at: fakeURL)

        #expect(importer.importErrorMessage != nil)
        let count = try await sessionManager.sessionCount()
        #expect(count == 0)
    }

    // MARK: - 空音声

    @Test("空（0フレーム）の WAV は取り込み失敗となりセッションが残らない")
    func rejectsEmptyAudio() async throws {
        let container = try makeContainer()
        let (importer, sessionManager) = makeImporter(container: container)

        let emptyURL = try makeWavFile(frameCount: 0)
        defer { try? FileManager.default.removeItem(at: emptyURL) }

        await importer.importFile(at: emptyURL)

        #expect(importer.importErrorMessage != nil)
        let count = try await sessionManager.sessionCount()
        #expect(count == 0)
    }

    // MARK: - 正常系（統合）

    @Test("合成 WAV のインポートでセッション作成・バッチ文字起こし・diarization が実行される")
    func importsWavAndRunsBatchPipeline() async throws {
        let container = try makeContainer()
        let transcription = MockTranscriptionEngine()
        await transcription.setStubbedSegments(to: [MockSegment(text: "こんにちは", start: 0, end: 1)])

        let embedding = makeNormalizedEmbedding(seed: 2.0)
        let diarization = MockDiarizationEngine(result: makeResult([("S1", 0, 1, embedding)]))

        let (importer, sessionManager) = makeImporter(
            container: container, transcription: transcription, diarization: diarization
        )

        let wavURL = try makeWavFile(frameCount: 16_000)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        await importer.importFile(at: wavURL)

        #expect(importer.importErrorMessage == nil)
        #expect(importer.isImporting == false)

        let sessions = try fetchSessions(container)
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.captureMode == "file")
        #expect(session.durationSeconds > 0)
        #expect(session.audioFileURL != nil)
        #expect(FileManager.default.fileExists(atPath: session.audioFilePath))

        #expect(session.segments.count == 1)
        #expect(session.segments.first?.text == "こんにちは")
        #expect(session.segments.first?.speakerLabel == "S1")
        #expect(session.segments.first?.speakerProfile != nil)

        let transcribeCallCount = await transcription.transcribeCallCount
        #expect(transcribeCallCount == 1)
        let diarizeCallCount = await diarization.diarizeCallCount
        #expect(diarizeCallCount == 1)

        let sessionCount = try await sessionManager.sessionCount()
        #expect(sessionCount == 1)
    }

    @Test("m4a ファイルもそのままコピーされて取り込める")
    func importsM4aFile() async throws {
        let container = try makeContainer()
        let (importer, _) = makeImporter(container: container)

        let m4aURL = try makeWavFile(frameCount: 16_000, ext: "m4a")
        defer { try? FileManager.default.removeItem(at: m4aURL) }

        await importer.importFile(at: m4aURL)

        #expect(importer.importErrorMessage == nil)
        let sessions = try fetchSessions(container)
        #expect(sessions.count == 1)
        #expect(sessions.first?.audioFileURL?.pathExtension == "m4a")
    }

    @Test("文字起こしが失敗すると取り込み全体が失敗しセッションが残らない")
    func transcriptionFailureRemovesSession() async throws {
        let container = try makeContainer()
        let transcription = MockTranscriptionEngine()
        await transcription.setShouldThrowOnTranscribe(true)
        let (importer, sessionManager) = makeImporter(container: container, transcription: transcription)

        let wavURL = try makeWavFile(frameCount: 16_000)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        await importer.importFile(at: wavURL)

        #expect(importer.importErrorMessage != nil)
        let count = try await sessionManager.sessionCount()
        #expect(count == 0)
        // ソースファイルは削除されない（コピー元の実ファイルなので）
        #expect(FileManager.default.fileExists(atPath: wavURL.path))
    }
}
