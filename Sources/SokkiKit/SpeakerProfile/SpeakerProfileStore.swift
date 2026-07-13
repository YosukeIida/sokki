import Foundation
import SwiftData
import os

actor SpeakerProfileStore {

    private let modelContext: ModelContext
    private var matcher: EmbeddingMatcher
    private let locale: Locale

    private static let diagnosticsLogger = Logger(subsystem: "com.sokki.app", category: "diagnostics")

    /// - Parameter locale: 自動命名（`SpeakerLabel`）の判定に用いるロケール。既定は `.current`。
    ///   テストでは ja/en を明示注入してグローバル状態に依存しない検証を行う。
    init(modelContext: ModelContext, matchThreshold: Float = 0.82, locale: Locale = .current) {
        self.modelContext = modelContext
        self.matcher = EmbeddingMatcher(threshold: matchThreshold)
        self.locale = locale
    }

    func updateThreshold(_ threshold: Float) {
        matcher = EmbeddingMatcher(threshold: threshold)
    }

    // diarization 結果を受け取り、speakerID → プロファイル識別子 のマッピングを返す。
    // `SpeakerProfileModel`（@Model）は Sendable でなく actor 境界を越えられないため、
    // 呼び出し側（別 actor の SessionManager など）が安全に扱えるよう PersistentIdentifier を返す（CLAUDE.md 規約）。
    func resolveProfiles(
        from diarization: DiarizationResult
    ) throws -> [String: PersistentIdentifier] {
        var profiles: [String: SpeakerProfileModel] = [:]
        let speakerEmbeddings = aggregatedEmbeddings(from: diarization)

        for (speakerID, embedding) in speakerEmbeddings {
#if DEBUG
            // TASK-27（レビュー指摘対応）: EmbeddingSimilarityReport は単一録音内の生 embedding
            // 同士の類似度しか測れず、実際に閾値判定へ使われる「セッション集約 embedding vs
            // 既存プロファイルの EMA embedding」の比較そのものは検証できないという指摘があった。
            // ここで実際に findOrCreate が使う比較対象・スコアをそのままログへ出すことで、
            // 録音間の再現性（同一人物が別録音でも正しく再認識されるか）を実データで確認できる。
            logCandidateScores(speakerID: speakerID, embedding: embedding)
#endif
            let profile = try findOrCreate(embedding: embedding)
            profiles[speakerID] = profile
        }
        // save 後に永続 ID が確定するため、マッピングは save 後に構築する。
        try modelContext.save()

        var mapping: [String: PersistentIdentifier] = [:]
        for (speakerID, profile) in profiles {
            mapping[speakerID] = profile.persistentModelID
        }
        return mapping
    }

    /// TASK-27 診断用: 指定した embedding と全既存プロファイル（過去セッションの EMA 更新済み
    /// embedding）とのコサイン類似度を、`findOrCreate` が実際に比較する対象そのままでスコア降順に
    /// 返す純粋関数。ログ出力（`logCandidateScores`）とテストの両方から使う。
    func candidateMatchScores(for embedding: [Float]) throws -> [(displayName: String, score: Float)] {
        let existing = try allProfiles()
        return existing
            .map { ($0.displayName, matcher.cosineSimilarity(embedding, $0.embedding)) }
            .sorted { $0.score > $1.score }
    }

    func rename(profileID: UUID, to name: String) throws {
        let descriptor = FetchDescriptor<SpeakerProfileModel>(
            predicate: #Predicate { $0.id == profileID }
        )
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        profile.displayName = name
        try modelContext.save()
    }

    func allProfiles() throws -> [SpeakerProfileModel] {
        let descriptor = FetchDescriptor<SpeakerProfileModel>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func deleteProfile(_ profileID: UUID) throws {
        let descriptor = FetchDescriptor<SpeakerProfileModel>(
            predicate: #Predicate { $0.id == profileID }
        )
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(profile)
        try modelContext.save()
    }

    // MARK: Private

#if DEBUG
    /// TASK-27 診断用: `candidateMatchScores` の結果を Logger（category "diagnostics"）へ INFO 出力する。
    /// `resolveProfiles` から DEBUG ビルド限定で呼ばれる（UI には出さない）。
    private func logCandidateScores(speakerID: String, embedding: [Float]) {
        guard let scores = try? candidateMatchScores(for: embedding), !scores.isEmpty else {
            Self.diagnosticsLogger.info(
                "[TASK-27 実照合] \(speakerID, privacy: .public): 既存プロファイルなし（新規作成）"
            )
            return
        }
        let formatted = scores
            .map { String(format: "%@=%.4f", $0.displayName, $0.score) }
            .joined(separator: ", ")
        let bestScore = scores[0].score
        let willMatch = bestScore >= matcher.threshold
        Self.diagnosticsLogger.info(
            "[TASK-27 実照合] \(speakerID, privacy: .public) 現閾値=\(self.matcher.threshold, format: .fixed(precision: 2)): \(formatted, privacy: .public) → \(willMatch ? "既存プロファイルへマッチ" : "新規プロファイル作成", privacy: .public)"
        )
    }
#endif

    private func findOrCreate(embedding: [Float]) throws -> SpeakerProfileModel {
        let existing = try allProfiles()

        if let match = matcher.bestMatch(query: embedding, candidates: existing) {
            match.updateEmbedding(with: embedding)
            return match
        }

        let count = existing.count
        let profile = SpeakerProfileModel(
            displayName: SpeakerLabel.displayName(index: count, locale: locale),
            embedding: embedding
        )
        modelContext.insert(profile)
        return profile
    }

    private func aggregatedEmbeddings(
        from result: DiarizationResult
    ) -> [String: [Float]] {
        var accumulator: [String: ([Float], Int)] = [:]

        for seg in result.segments {
            guard let emb = seg.embedding else { continue }
            if var (sum, count) = accumulator[seg.speakerID] {
                sum = zip(sum, emb).map(+)
                accumulator[seg.speakerID] = (sum, count + 1)
            } else {
                accumulator[seg.speakerID] = (emb, 1)
            }
        }

        return accumulator.mapValues { (sum, count) in
            l2Normalize(sum.map { $0 / Float(count) })
        }
    }
}
