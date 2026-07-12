import Foundation
import SwiftData
import Testing
@testable import SokkiKit

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

        let base = makeNormalizedEmbedding(seed: 2.0)
        // わずかに違う方向（閾値 0.82 は超える近さ）の embedding で 2 回目を解決する
        let nudged = l2Normalize(zip(base, makeNormalizedEmbedding(seed: 2.05)).map { $0 + $1 * 0.02 })

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

    // MARK: - TASK-30: SpeakerProfileView UI（名前編集・声紋削除）で使う永続化・参照整合の検証

    @Test("rename は永続化され、別 ModelContext から再取得しても反映されている（インメモリ）")
    func renamePersistsAcrossContextsInMemory() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SessionModel.self, SegmentModel.self, SpeakerProfileModel.self, AppSettingsModel.self,
            configurations: config
        )
        // store には専用の ModelContext を渡す（actor 境界を越えて同一インスタンスを
        // 使い回さない。既存の resolvesAcrossStoreReopen と同じ流儀）。
        let store = SpeakerProfileStore(modelContext: ModelContext(container))

        let embedding = makeNormalizedEmbedding(seed: 5.0)
        _ = try await store.resolveProfiles(from: makeResult([("S1", 0, 5, embedding)]))

        let readContext = ModelContext(container)
        let before = try #require(readContext.fetch(FetchDescriptor<SpeakerProfileModel>()).first)
        let profileID = before.id
        #expect(before.displayName != "田中 太郎") // rename 前は自動命名（「話者 N」）であること

        try await store.rename(profileID: profileID, to: "田中 太郎")

        // 同一 ModelContainer に対する別 ModelContext から再取得しても反映されていること
        let otherContext = ModelContext(container)
        let renamed = try otherContext.fetch(FetchDescriptor<SpeakerProfileModel>(
            predicate: #Predicate { $0.id == profileID }
        )).first
        #expect(renamed?.displayName == "田中 太郎")
    }

    @Test("プロファイル削除時、紐づくセグメントは残り speakerProfile 参照が nil になる（dangling 参照にならない）")
    func deletingProfileNullifiesSegmentReference() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SessionModel.self, SegmentModel.self, SpeakerProfileModel.self, AppSettingsModel.self,
            configurations: config
        )
        let store = SpeakerProfileStore(modelContext: ModelContext(container))

        let embedding = makeNormalizedEmbedding(seed: 42.0)
        _ = try await store.resolveProfiles(from: makeResult([("S1", 0, 5, embedding)]))

        // このプロファイルに紐づくセグメント（発話記録）を作成して保存する。
        // store の内部 ModelContext とは別インスタンスを使い、actor 境界を越えて共有しない。
        let setupContext = ModelContext(container)
        let profile = try #require(setupContext.fetch(FetchDescriptor<SpeakerProfileModel>()).first)
        let profileID = profile.id

        let session = SessionModel(title: "テスト", audioFilePath: "", captureMode: "mic")
        let segment = SegmentModel(start: 0, end: 3, text: "こんにちは")
        segment.speakerProfile = profile
        session.segments.append(segment)
        setupContext.insert(session)
        try setupContext.save()
        let segmentID = segment.id

        // 削除前提として、確かにセグメントがこのプロファイルへ紐づいていることを確認する
        // （nullify を検証したことにするための前提が崩れていないかのガード）。
        let linkedBeforeDelete = try setupContext.fetch(FetchDescriptor<SegmentModel>(
            predicate: #Predicate { $0.id == segmentID }
        )).first
        #expect(linkedBeforeDelete?.speakerProfile?.id == profileID)

        try await store.deleteProfile(profileID)

        // プロファイル自体は削除される
        let verifyContext = ModelContext(container)
        let remainingProfiles = try verifyContext.fetch(FetchDescriptor<SpeakerProfileModel>())
        #expect(remainingProfiles.isEmpty)

        // セグメントは削除されず残り、speakerProfile 参照は nil になっている（dangling 参照にならない）
        let segments = try verifyContext.fetch(FetchDescriptor<SegmentModel>(
            predicate: #Predicate { $0.id == segmentID }
        ))
        #expect(segments.count == 1)
        #expect(segments.first?.speakerProfile == nil)
        #expect(segments.first?.text == "こんにちは")
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

        for (a, b) in zip(profile.embedding, expected) {
            #expect(abs(a - b) < 1e-5)
        }
        #expect(profile.embeddingCount == 2)
        #expect(profile.lastSeenAt > createdLastSeen)
    }
}
