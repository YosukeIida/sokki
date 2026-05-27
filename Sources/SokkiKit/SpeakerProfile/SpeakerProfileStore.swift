import Foundation
import SwiftData

actor SpeakerProfileStore {

    private let modelContext: ModelContext
    private var matcher: EmbeddingMatcher

    init(modelContext: ModelContext, matchThreshold: Float = 0.82) {
        self.modelContext = modelContext
        self.matcher = EmbeddingMatcher(threshold: matchThreshold)
    }

    func updateThreshold(_ threshold: Float) {
        matcher = EmbeddingMatcher(threshold: threshold)
    }

    // diarization 結果を受け取り、speakerID → プロファイル のマッピングを返す
    func resolveProfiles(
        from diarization: DiarizationResult
    ) throws -> [String: SpeakerProfileModel] {
        var mapping: [String: SpeakerProfileModel] = [:]
        let speakerEmbeddings = aggregatedEmbeddings(from: diarization)

        for (speakerID, embedding) in speakerEmbeddings {
            let profile = try findOrCreate(embedding: embedding)
            mapping[speakerID] = profile
        }
        try modelContext.save()
        return mapping
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

    private func findOrCreate(embedding: [Float]) throws -> SpeakerProfileModel {
        let existing = try allProfiles()

        if let match = matcher.bestMatch(query: embedding, candidates: existing) {
            match.updateEmbedding(with: embedding)
            return match
        }

        let count = existing.count
        let profile = SpeakerProfileModel(
            displayName: "話者 \(count + 1)",
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
