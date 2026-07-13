import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import SokkiKit

/// TASK-25: diarization → SpeakerProfileStore 配線の結合テスト。
/// パイプラインの停止後フローに相当する `applyDiarization` / `diarizeAndAssign` を直接駆動し、
/// SegmentModel に speakerProfile が紐づくこと、findOrCreate / EMA が実働することを検証する。
@Suite("DiarizationPipeline")
@MainActor
struct DiarizationPipelineTests {

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: SessionModel.self,
                 SegmentModel.self,
                 SpeakerProfileModel.self,
                 AppSettingsModel.self,
            configurations: config
        )
    }

    private func makePipeline(
        container: ModelContainer,
        diarization: MockDiarizationEngine
    ) -> (pipeline: TranscriptionPipeline, sessionManager: SessionManager, store: SpeakerProfileStore) {
        let store = SpeakerProfileStore(modelContext: ModelContext(container))
        let sessionManager = SessionManager(modelContainer: container)
        let pipeline = TranscriptionPipeline(
            captureManager: AudioCaptureManager(),
            transcriptionEngine: MockTranscriptionEngine(),
            diarizationEngine: diarization,
            speakerStore: store,
            sessionManager: sessionManager
        )
        return (pipeline, sessionManager, store)
    }

    /// speakerID / 時間区間 / embedding から DiarizationResult を組み立てる。
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

    private func fetchSegments(_ container: ModelContainer) throws -> [SegmentModel] {
        let ctx = ModelContext(container)
        return try ctx.fetch(FetchDescriptor<SegmentModel>(sortBy: [SortDescriptor(\.start)]))
    }

    private func fetchProfiles(_ container: ModelContainer) throws -> [SpeakerProfileModel] {
        let ctx = ModelContext(container)
        return try ctx.fetch(FetchDescriptor<SpeakerProfileModel>())
    }

    // MARK: - Tests

    @Test("diarization 結果が SegmentModel.speakerProfile に紐づく")
    func assignsSpeakerProfileToSegment() async throws {
        let container = try makeContainer()
        let embedding = makeNormalizedEmbedding(seed: 1.0)
        let mock = MockDiarizationEngine(
            result: makeResult([("S1", 0, 5, embedding)])
        )
        let (pipeline, sessionManager, _) = makePipeline(container: container, diarization: mock)

        let sid = try await sessionManager.createSession(title: "会議", mode: .micOnly)
        try await sessionManager.appendSegment(
            MockSegment(text: "こんにちは", start: 0, end: 5), toSessionID: sid
        )

        try await pipeline.applyDiarization(audioSamples: [0, 0, 0], sessionID: sid)

        let segments = try fetchSegments(container)
        #expect(segments.count == 1)
        #expect(segments.first?.speakerLabel == "S1")
        #expect(segments.first?.speakerProfile != nil)
        #expect(segments.first?.speakerProfile?.displayName == "話者 1")

        let profiles = try fetchProfiles(container)
        #expect(profiles.count == 1)
        #expect(profiles.first?.embeddingCount == 1)
    }

    @Test("重なりが最大の話者が各セグメントに割り当てられる")
    func assignsByMaximumOverlap() async throws {
        let container = try makeContainer()
        let embA = makeNormalizedEmbedding(seed: 1.0)
        let embB = makeNormalizedEmbedding(seed: 50.0)
        let mock = MockDiarizationEngine(
            result: makeResult([
                ("S1", 0, 10, embA),
                ("S2", 10, 20, embB),
            ])
        )
        let (pipeline, sessionManager, _) = makePipeline(container: container, diarization: mock)

        let sid = try await sessionManager.createSession(title: "会議", mode: .micOnly)
        // seg1 は S1 区間に完全に含まれる / seg2 は S2 区間に多く重なる
        try await sessionManager.appendSegment(MockSegment(text: "a", start: 1, end: 4), toSessionID: sid)
        try await sessionManager.appendSegment(MockSegment(text: "b", start: 9, end: 16), toSessionID: sid)

        try await pipeline.applyDiarization(audioSamples: [0], sessionID: sid)

        let segments = try fetchSegments(container)
        #expect(segments.count == 2)
        #expect(segments[0].speakerLabel == "S1")
        #expect(segments[1].speakerLabel == "S2")
        #expect(segments[0].speakerProfile?.id != segments[1].speakerProfile?.id)
    }

    @Test("2 回目の録音で同一 embedding が同一プロファイルに解決され EMA 更新される")
    func reusesProfileAcrossRecordings() async throws {
        let container = try makeContainer()
        let embedding = makeNormalizedEmbedding(seed: 3.0)
        let mock = MockDiarizationEngine(result: makeResult([("S1", 0, 5, embedding)]))
        let (pipeline, sessionManager, _) = makePipeline(container: container, diarization: mock)

        // 1 回目
        let sid1 = try await sessionManager.createSession(title: "録音1", mode: .micOnly)
        try await sessionManager.appendSegment(MockSegment(text: "one", start: 0, end: 5), toSessionID: sid1)
        try await pipeline.applyDiarization(audioSamples: [0], sessionID: sid1)

        // 2 回目（別セッション・同一話者 embedding。speakerID が別ラベルでも embedding で照合されるべき）
        await mock.setResult(makeResult([("S9", 0, 5, embedding)]))
        let sid2 = try await sessionManager.createSession(title: "録音2", mode: .micOnly)
        try await sessionManager.appendSegment(MockSegment(text: "two", start: 0, end: 5), toSessionID: sid2)
        try await pipeline.applyDiarization(audioSamples: [0], sessionID: sid2)

        let profiles = try fetchProfiles(container)
        #expect(profiles.count == 1)                 // 新規作成されず同一プロファイルに解決
        #expect(profiles.first?.embeddingCount == 2) // EMA 更新が 1 回走った
    }

    @Test("diarize が throw してもセッション・セグメントは保持される")
    func diarizationFailureDoesNotBreakSession() async throws {
        let container = try makeContainer()
        let mock = MockDiarizationEngine(isReady: true, errorToThrow: MockDiarizationError.forced)
        let (pipeline, sessionManager, _) = makePipeline(container: container, diarization: mock)

        let sid = try await sessionManager.createSession(title: "失敗", mode: .micOnly)
        try await sessionManager.appendSegment(MockSegment(text: "残る", start: 0, end: 5), toSessionID: sid)

        // 非スロー: 失敗はログのみで握りつぶされる
        await pipeline.diarizeAndAssign(audioSamples: [0], sessionID: sid)

        let segments = try fetchSegments(container)
        #expect(segments.count == 1)
        #expect(segments.first?.text == "残る")
        #expect(segments.first?.speakerProfile == nil) // 割り当ては行われない

        let profiles = try fetchProfiles(container)
        #expect(profiles.isEmpty)
    }

    @Test("stop() を 2 回呼んでも diarization は 1 回だけ実行され embeddingCount は二重加算されない")
    func stopIsReentrantSafe() async throws {
        let container = try makeContainer()
        let embedding = makeNormalizedEmbedding(seed: 7.0)
        let mock = MockDiarizationEngine(result: makeResult([("S1", 0, 5, embedding)]))
        let (pipeline, sessionManager, _) = makePipeline(container: container, diarization: mock)

        let sid = try await sessionManager.createSession(title: "reentry", mode: .micOnly)
        try await sessionManager.appendSegment(MockSegment(text: "x", start: 0, end: 5), toSessionID: sid)

        // stop() が実際に diarization を走らせるよう、読み込める録音ファイルを session の audioURL へ用意する。
        let url = try #require(await sessionManager.audioURL(forSessionID: sid))
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        )!
        let writer = try AudioFileWriter(url: url, processingFormat: format)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buf.frameLength = 16_000
        writer.write(buf)
        writer.close()

        pipeline.primeForStopTesting(sessionID: sid)
        try await pipeline.stop()   // 1 回目: diarization 実行
        try await pipeline.stop()   // 2 回目: 再入ガードで no-op

        let profiles = try fetchProfiles(container)
        #expect(profiles.count == 1)
        #expect(profiles.first?.embeddingCount == 1)   // 二重加算されない
        let diarizeCalls = await mock.diarizeCallCount
        #expect(diarizeCalls == 1)
    }

    @Test("diarizationEnabled=false のとき既定は有効・false で無効を返す")
    func diarizationEnabledReflectsSettings() async throws {
        let container = try makeContainer()
        let sessionManager = SessionManager(modelContainer: container)

        // 未保存時は既定で有効
        let defaultEnabled = await sessionManager.diarizationEnabled()
        #expect(defaultEnabled == true)

        // 無効設定を保存
        let ctx = ModelContext(container)
        let settings = AppSettingsModel()
        settings.diarizationEnabled = false
        ctx.insert(settings)
        try ctx.save()

        let disabled = await sessionManager.diarizationEnabled()
        #expect(disabled == false)
    }

    // MARK: - 声紋照合閾値の配線（TASK-27）

    @Test("未保存時は embeddingMatchThreshold の既定値 0.82 を返す")
    func embeddingMatchThresholdDefaultsTo082() async throws {
        let container = try makeContainer()
        let sessionManager = SessionManager(modelContainer: container)

        let threshold = await sessionManager.embeddingMatchThreshold()
        #expect(abs(threshold - 0.82) < 1e-6)
    }

    @Test(
        "破損・範囲外の embeddingMatchThreshold は既定値へフォールバックまたは範囲へクランプされる（レビュー指摘の回帰テスト）",
        arguments: [
            // NOTE: SwiftData/SQLite の永続化を経ると Float.nan は 0.0 に丸められる（実測確認済み）。
            // そのため NaN は「0.0 として読み出され 0.5 にクランプされる」経路になる。
            // ±infinity は永続化後も非有限のまま読み出されるため isFinite ガードで既定値 0.82 に落ちる。
            (Float.nan, Float(0.5)),
            (Float.infinity, Float(0.82)),
            (-Float.infinity, Float(0.82)),
            (Float(-1.0), Float(0.5)),
            (Float(0.0), Float(0.5)),
            (Float(1.0), Float(0.95)),
        ]
    )
    func embeddingMatchThresholdHandlesCorruptedValues(stored: Float, expected: Float) async throws {
        let container = try makeContainer()
        let sessionManager = SessionManager(modelContainer: container)

        let ctx = ModelContext(container)
        let settings = AppSettingsModel()
        settings.embeddingMatchThreshold = stored
        ctx.insert(settings)
        try ctx.save()

        let threshold = await sessionManager.embeddingMatchThreshold()
        #expect(abs(threshold - expected) < 1e-6)
    }

    @Test("設定に保存された embeddingMatchThreshold が読み取られる")
    func embeddingMatchThresholdReflectsSettings() async throws {
        let container = try makeContainer()
        let sessionManager = SessionManager(modelContainer: container)

        let ctx = ModelContext(container)
        let settings = AppSettingsModel()
        settings.embeddingMatchThreshold = 0.95
        ctx.insert(settings)
        try ctx.save()

        let threshold = await sessionManager.embeddingMatchThreshold()
        #expect(abs(threshold - 0.95) < 1e-6)
    }

    @Test("設定の閾値が厳しいほど同一話者の再利用がされにくくなる（配線の実効性を確認）")
    func thresholdSettingChangesMatchingBehavior() async throws {
        // S1 の2発話の類似度を 0.90 に固定する。
        // 既定閾値 0.82 なら同一プロファイルに解決され、設定で 0.95 に引き上げると別プロファイルになる。
        let pair = makeEmbeddingPair(cosineSimilarity: 0.90)

        // 既定閾値（0.82）: マージされ 1 プロファイル
        do {
            let container = try makeContainer()
            let mock = MockDiarizationEngine(result: makeResult([("S1", 0, 5, pair.a)]))
            let (pipeline, sessionManager, _) = makePipeline(container: container, diarization: mock)

            let sid1 = try await sessionManager.createSession(title: "録音1", mode: .micOnly)
            try await sessionManager.appendSegment(MockSegment(text: "one", start: 0, end: 5), toSessionID: sid1)
            try await pipeline.applyDiarization(audioSamples: [0], sessionID: sid1)

            await mock.setResult(makeResult([("S9", 0, 5, pair.b)]))
            let sid2 = try await sessionManager.createSession(title: "録音2", mode: .micOnly)
            try await sessionManager.appendSegment(MockSegment(text: "two", start: 0, end: 5), toSessionID: sid2)
            try await pipeline.applyDiarization(audioSamples: [0], sessionID: sid2)

            let profiles = try fetchProfiles(container)
            #expect(profiles.count == 1)
        }

        // 閾値を 0.95 に設定: マージされず 2 プロファイル（配線が効いていることの確認）
        do {
            let container = try makeContainer()
            let ctx = ModelContext(container)
            let settings = AppSettingsModel()
            settings.embeddingMatchThreshold = 0.95
            ctx.insert(settings)
            try ctx.save()

            let mock = MockDiarizationEngine(result: makeResult([("S1", 0, 5, pair.a)]))
            let (pipeline, sessionManager, _) = makePipeline(container: container, diarization: mock)

            let sid1 = try await sessionManager.createSession(title: "録音1", mode: .micOnly)
            try await sessionManager.appendSegment(MockSegment(text: "one", start: 0, end: 5), toSessionID: sid1)
            try await pipeline.applyDiarization(audioSamples: [0], sessionID: sid1)

            await mock.setResult(makeResult([("S9", 0, 5, pair.b)]))
            let sid2 = try await sessionManager.createSession(title: "録音2", mode: .micOnly)
            try await sessionManager.appendSegment(MockSegment(text: "two", start: 0, end: 5), toSessionID: sid2)
            try await pipeline.applyDiarization(audioSamples: [0], sessionID: sid2)

            let profiles = try fetchProfiles(container)
            #expect(profiles.count == 2)
        }
    }

    // MARK: - 実照合スコアの診断（レビュー指摘対応・TASK-27）

    @Test("candidateMatchScores は既存プロファイルが無ければ空配列を返す")
    func candidateMatchScoresEmptyWhenNoProfiles() async throws {
        let container = try makeContainer()
        let store = SpeakerProfileStore(modelContext: ModelContext(container))

        let query = makeNormalizedEmbedding(seed: 1.0)
        let scores = try await store.candidateMatchScores(for: query)
        #expect(scores.isEmpty)
    }

    @Test("candidateMatchScores は resolveProfiles が実際に使う比較（集約 embedding vs 既存プロファイルの EMA embedding）と同じスコアをスコア降順で返す")
    func candidateMatchScoresReflectsActualMatching() async throws {
        let container = try makeContainer()
        let embedding = makeNormalizedEmbedding(seed: 3.0)
        let mock = MockDiarizationEngine(result: makeResult([("S1", 0, 5, embedding)]))
        let (pipeline, sessionManager, store) = makePipeline(container: container, diarization: mock)

        // 1 回目の録音でプロファイルを作成する。
        let sid1 = try await sessionManager.createSession(title: "録音1", mode: .micOnly)
        try await sessionManager.appendSegment(MockSegment(text: "one", start: 0, end: 5), toSessionID: sid1)
        try await pipeline.applyDiarization(audioSamples: [0], sessionID: sid1)

        let profiles = try fetchProfiles(container)
        #expect(profiles.count == 1)

        // 同一 embedding を問い合わせると、findOrCreate が bestMatch で使うのと同じ
        // コサイン類似度（≈1.0）が返る。
        let scores = try await store.candidateMatchScores(for: embedding)
        #expect(scores.count == 1)
        #expect(scores[0].displayName == "話者 1")
        #expect(abs(scores[0].score - 1.0) < 1e-4)

        // 逆方向の embedding（コサイン類似度 = -1.0 になることが幾何学的に保証される）を
        // 問い合わせると、既定閾値 0.82 を下回るスコアが返る
        // （実際に resolveProfiles が新規プロファイルを作る根拠と一致する）。
        let opposite = embedding.map { -$0 }
        let lowScores = try await store.candidateMatchScores(for: opposite)
        #expect(lowScores.count == 1)
        #expect(abs(lowScores[0].score - (-1.0)) < 1e-4)
        #expect(lowScores[0].score < 0.82)
    }

    @Test("candidateMatchScores は複数プロファイルをスコア降順で返す")
    func candidateMatchScoresSortedDescending() async throws {
        let container = try makeContainer()
        let store = SpeakerProfileStore(modelContext: ModelContext(container))

        let query = makeNormalizedEmbedding(seed: 10.0)
        let closeEmbedding = makeNormalizedEmbedding(seed: 10.05)   // query に近い
        let farEmbedding = makeNormalizedEmbedding(seed: 200.0)     // query から遠い

        _ = try await store.candidateMatchScores(for: query)  // 副作用なし（読み取り専用）であることの確認を兼ねる
        try await store.resolveProfiles(from: DiarizationResult(
            segments: [
                DiarizationSegment(start: 0, end: 1, speakerID: "far", embedding: farEmbedding),
                DiarizationSegment(start: 1, end: 2, speakerID: "close", embedding: closeEmbedding),
            ],
            numberOfSpeakers: 2
        ))

        let scores = try await store.candidateMatchScores(for: query)
        #expect(scores.count == 2)
        #expect(scores[0].score >= scores[1].score)  // 降順
    }
}
