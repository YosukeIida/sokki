import Testing
import Foundation
import SwiftData
@testable import SokkiKit

// MARK: - Helpers

/// テスト専用: `@Model` の `SpeakerProfileModel` を actor 境界を越えて直接返さず、
/// Sendable な displayName の集合に変換して返す（Phase1AudioSaveTests.swift の
/// allSessionSnapshots() と同じ方針）。
extension SpeakerProfileStore {
    fileprivate func autoNamedDisplayNames(from diarization: DiarizationResult) throws -> Set<String> {
        let mapping = try resolveProfiles(from: diarization)
        return Set(mapping.values.map(\.displayName))
    }
}

@Suite("SpeakerProfileStore 自動命名（TASK-38: ロケール追従 SpeakerLabel）")
struct SpeakerProfileStoreNamingTests {

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

    /// axis 番目だけを 1.0 にした 256 次元の基底ベクトル。互いに直交する（コサイン類似度 0）
    /// ため、EmbeddingMatcher の閾値（既定 0.82）を超えず、常に新規話者として作成される。
    private func orthogonalEmbedding(axis: Int, dimension: Int = 256) -> [Float] {
        var v = [Float](repeating: 0, count: dimension)
        v[axis] = 1.0
        return v
    }

    private func makeDiarizationResult(speakerCount: Int) -> DiarizationResult {
        let segments = (0..<speakerCount).map { i in
            DiarizationSegment(
                start: Double(i),
                end: Double(i) + 1,
                speakerID: "SPEAKER_\(i)",
                embedding: orthogonalEmbedding(axis: i)
            )
        }
        return DiarizationResult(segments: segments, numberOfSpeakers: speakerCount)
    }

    @Test("日本語ロケール: 新規話者は 話者A / 話者B の形式で命名される")
    func japaneseAutoNaming() async throws {
        let container = try makeContainer()
        let store = SpeakerProfileStore(
            modelContext: ModelContext(container),
            locale: Locale(identifier: "ja_JP")
        )

        let names = try await store.autoNamedDisplayNames(
            from: makeDiarizationResult(speakerCount: 2)
        )

        #expect(names == ["話者A", "話者B"])
    }

    @Test("英語ロケール: 新規話者は Speaker A / Speaker B の形式で命名される")
    func englishAutoNaming() async throws {
        let container = try makeContainer()
        let store = SpeakerProfileStore(
            modelContext: ModelContext(container),
            locale: Locale(identifier: "en_US")
        )

        let names = try await store.autoNamedDisplayNames(
            from: makeDiarizationResult(speakerCount: 2)
        )

        #expect(names == ["Speaker A", "Speaker B"])
    }

    @Test("3人目以降も桁上げせず A〜Z の範囲でロールオーバーする（26人目で AA）")
    func rolloverAtTwentySeventhSpeaker() async throws {
        let container = try makeContainer()
        let store = SpeakerProfileStore(
            modelContext: ModelContext(container),
            locale: Locale(identifier: "en_US")
        )

        let names = try await store.autoNamedDisplayNames(
            from: makeDiarizationResult(speakerCount: 27)
        )

        #expect(names.contains("Speaker Z"))
        #expect(names.contains("Speaker AA"))
        #expect(names.count == 27)
    }
}
