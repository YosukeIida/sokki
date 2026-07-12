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
}
