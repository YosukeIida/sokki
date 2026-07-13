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

/// TASK-28: 話者プロファイル永続化（EMA）のセッション横断認識を検証する。
/// findOrCreate / EMA 更新自体は TASK-25 で実装済み（`SpeakerProfileStore.swift` /
/// `SpeakerProfileModel.updateEmbedding`）。本テストは以下のギャップを埋める：
///   - `DiarizationPipelineTests` は同一 `ModelContainer` 内での「2 回目の録音」までしか検証しておらず、
///     実際のアプリ再起動（ストア再オープン）相当のシナリオは未検証だった
///   - EMA 後の embedding が L2 正規化を維持すること（閾値 0.82 の意味を保つ）の直接検証
///   - 削除済みプロファイルが同一 embedding の再出現で復活しないことの検証
@Suite("SpeakerProfileStore")
@MainActor
struct SpeakerProfileStoreTests {

    // MARK: - Fixtures

    /// 一意な一時ディレクトリに SwiftData ストアを作る。
    /// テスト終了時にディレクトリごと削除し、SQLite の sidecar ファイル（-wal/-shm）も掃除する。
    private func makeTempStoreDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sokkiTest_speakerStore_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 指定 URL をファイルストアとする `ModelContainer` を生成する。
    /// 同一 URL で複数回呼ぶことで「アプリ再起動 = ストア再オープン」を模倣できる。
    private func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(
            for: SessionModel.self,
                 SegmentModel.self,
                 SpeakerProfileModel.self,
                 AppSettingsModel.self,
            configurations: config
        )
    }

    private func makeResult(
        _ specs: [(speakerID: String, start: Double, end: Double, embedding: [Float])]
    ) -> DiarizationResult {
        let segments = specs.map {
            DiarizationSegment(start: $0.start, end: $0.end, speakerID: $0.speakerID, embedding: $0.embedding)
        }
        return DiarizationResult(segments: segments, numberOfSpeakers: Set(specs.map { $0.speakerID }).count)
    }

    // MARK: - Tests

    @Test("ストア再オープン（新しい ModelContainer）後も同一 embedding が同一プロファイルに解決され EMA 更新される")
    func resolvesAcrossStoreReopen() async throws {
        let dir = makeTempStoreDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("speaker.store")

        let embedding = makeNormalizedEmbedding(seed: 7.0)

        // 録音1: 新規プロファイルが作成される
        var firstProfileID: UUID?
        do {
            let container = try makeContainer(at: storeURL)
            let store = SpeakerProfileStore(modelContext: ModelContext(container))
            let mapping = try await store.resolveProfiles(from: makeResult([("S1", 0, 5, embedding)]))
            #expect(mapping.count == 1)

            let ctx = ModelContext(container)
            let profiles = try ctx.fetch(FetchDescriptor<SpeakerProfileModel>())
            #expect(profiles.count == 1)
            #expect(profiles.first?.embeddingCount == 1)
            firstProfileID = profiles.first?.id
        }
        // ここで container / store がスコープを抜ける。次のブロックは実ファイルへの永続化のみを
        // 頼りに、別インスタンスの ModelContainer から同じストアを読み直す（＝アプリ再起動相当）。

        // 録音2: 別 ModelContainer で同一 embedding を解決 → 同一プロファイルに解決されるべき
        do {
            let container = try makeContainer(at: storeURL)
            let store = SpeakerProfileStore(modelContext: ModelContext(container))
            let mapping = try await store.resolveProfiles(from: makeResult([("S9", 0, 5, embedding)]))
            #expect(mapping["S9"] != nil)

            let ctx = ModelContext(container)
            let profiles = try ctx.fetch(FetchDescriptor<SpeakerProfileModel>())
            #expect(profiles.count == 1) // 新規作成されず同一プロファイルへ解決
            #expect(profiles.first?.id == firstProfileID)
            #expect(profiles.first?.embeddingCount == 2) // EMA 更新で加算
        }
    }

    @Test("EMA 更新後の embedding は L2 正規化を維持する（閾値 0.82 の意味を保つ）")
    func emaUpdateStaysNormalized() async throws {
        let dir = makeTempStoreDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("speaker.store")
        let container = try makeContainer(at: storeURL)
        let store = SpeakerProfileStore(modelContext: ModelContext(container))

        // cos(base, nudged) = 0.85 に固定する（閾値 0.82 は超えつつ、生の EMA 合成ベクトル
        // （0.9*base + 0.1*nudged, 未正規化）のノルムが 1.0 から 0.0136 ずれるよう意図的に選ぶ。
        // 単に近い方向のベクトル同士（cos ≈ 0.9999）だと、正規化を行わなくても合成ベクトルの
        // ノルムがほぼ 1.0 になってしまい、`l2Normalize` の呼び出し漏れという退行を検出できない。
        let base: [Float] = [1, 0]
        let nudged: [Float] = [0.85, (1 - Float(0.85) * Float(0.85)).squareRoot()]

        _ = try await store.resolveProfiles(from: makeResult([("S1", 0, 5, base)]))
        _ = try await store.resolveProfiles(from: makeResult([("S1", 0, 5, nudged)]))

        let ctx = ModelContext(container)
        let profiles = try ctx.fetch(FetchDescriptor<SpeakerProfileModel>())
        #expect(profiles.count == 1) // 別プロファイルにならず EMA 更新されたことの前提確認
        #expect(profiles.first?.embeddingCount == 2)

        let updated = profiles.first!.embedding
        var normSq: Float = 0
        for v in updated { normSq += v * v }
        #expect(abs(normSq.squareRoot() - 1.0) < 1e-4)
    }

    @Test("削除済みプロファイルは同一 embedding が再出現しても復活せず、新規プロファイルが作られる")
    func deletedProfileDoesNotResurrect() async throws {
        let dir = makeTempStoreDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("speaker.store")
        let container = try makeContainer(at: storeURL)
        let store = SpeakerProfileStore(modelContext: ModelContext(container))

        let embedding = makeNormalizedEmbedding(seed: 11.0)
        let mapping1 = try await store.resolveProfiles(from: makeResult([("S1", 0, 5, embedding)]))
        #expect(mapping1["S1"] != nil)

        let ctx = ModelContext(container)
        let firstProfiles = try ctx.fetch(FetchDescriptor<SpeakerProfileModel>())
        #expect(firstProfiles.count == 1)
        let deletedID = firstProfiles.first!.id

        try await store.deleteProfile(deletedID)
        let afterDelete = try ctx.fetch(FetchDescriptor<SpeakerProfileModel>())
        #expect(afterDelete.isEmpty)

        // 同一 embedding が再出現しても、削除済みプロファイルは復活せず新規作成される
        _ = try await store.resolveProfiles(from: makeResult([("S1", 0, 5, embedding)]))
        let afterResolve = try ctx.fetch(FetchDescriptor<SpeakerProfileModel>())
        #expect(afterResolve.count == 1)
        #expect(afterResolve.first?.id != deletedID)
        #expect(afterResolve.first?.embeddingCount == 1) // EMA 更新ではなく新規作成である証跡
    }

    @Test("EMA は既定 alpha=0.1 で更新され、更新後の embeddingCount / lastSeenAt が進む")
    func emaAlphaMatchesSpecAndMetadataAdvances() throws {
        let base: [Float] = l2Normalize(Array(repeating: Float(1), count: 4))
        let profile = SpeakerProfileModel(displayName: "test", embedding: base)
        let createdLastSeen = profile.lastSeenAt
        let newEmbedding: [Float] = l2Normalize([1, 0, 0, 0])

        Thread.sleep(forTimeInterval: 0.01) // lastSeenAt の前進を検知できるよう僅かに間隔を空ける
        profile.updateEmbedding(with: newEmbedding) // alpha は既定の 0.1

        let expectedRaw = zip(base, newEmbedding).map { (1 - Float(0.1)) * $0 + Float(0.1) * $1 }
        let expected = l2Normalize(expectedRaw)

        // `zip` は短い方の長さに揃えてしまうため、次元数が一致することを先に確認しないと、
        // embedding が空/短縮される退行があっても成分比較が恒真（0 回ループ）になり検出できない。
        #expect(profile.embedding.count == expected.count)
        for (a, b) in zip(profile.embedding, expected) {
            #expect(abs(a - b) < 1e-5)
        }
        #expect(profile.embeddingCount == 2)
        #expect(profile.lastSeenAt > createdLastSeen)
    }
}
