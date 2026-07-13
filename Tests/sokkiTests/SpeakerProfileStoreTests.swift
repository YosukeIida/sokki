import Testing
import Foundation
import SwiftData
@testable import SokkiKit

// MARK: - Helpers

/// テスト専用: `resolveProfiles` は `@Model` を actor 境界越えで返さず PersistentIdentifier を
/// 返す（CLAUDE.md 規約）ため、container の別 ModelContext で再取得して Sendable な
/// displayName 集合へ変換する（Phase1AudioSaveTests.swift の allSessionSnapshots() と同じ方針）。
private func autoNamedDisplayNames(
    store: SpeakerProfileStore,
    container: ModelContainer,
    from diarization: DiarizationResult
) async throws -> Set<String> {
    let ids = Set(try await store.resolveProfiles(from: diarization).values)
    let context = ModelContext(container)
    let profiles = try context.fetch(FetchDescriptor<SpeakerProfileModel>())
    return Set(profiles.filter { ids.contains($0.persistentModelID) }.map(\.displayName))
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

        let names = try await autoNamedDisplayNames(
            store: store, container: container,
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

        let names = try await autoNamedDisplayNames(
            store: store, container: container,
            from: makeDiarizationResult(speakerCount: 2)
        )

        #expect(names == ["Speaker A", "Speaker B"])
    }

    @Test("26人目までは A〜Z、27人目で AA に桁上げする")
    func rolloverAtTwentySeventhSpeaker() async throws {
        let container = try makeContainer()
        let store = SpeakerProfileStore(
            modelContext: ModelContext(container),
            locale: Locale(identifier: "en_US")
        )

        let names = try await autoNamedDisplayNames(
            store: store, container: container,
            from: makeDiarizationResult(speakerCount: 27)
        )

        #expect(names.contains("Speaker Z"))
        #expect(names.contains("Speaker AA"))
        #expect(names.count == 27)
    }
}
