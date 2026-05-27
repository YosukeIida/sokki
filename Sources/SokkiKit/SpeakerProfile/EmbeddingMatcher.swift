import Accelerate
import Foundation

struct EmbeddingMatcher {

    let threshold: Float

    init(threshold: Float = 0.82) {
        self.threshold = threshold
    }

    func bestMatch(
        query: [Float],
        candidates: [SpeakerProfileModel]
    ) -> SpeakerProfileModel? {
        guard !candidates.isEmpty else { return nil }

        var best: (profile: SpeakerProfileModel, score: Float)? = nil

        for candidate in candidates {
            let score = cosineSimilarity(query, candidate.embedding)
            if score >= threshold {
                if best == nil || score > best!.score {
                    best = (candidate, score)
                }
            }
        }
        return best?.profile
    }

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dotProduct / denom
    }
}

func l2Normalize(_ v: [Float]) -> [Float] {
    var norm: Float = 0
    vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
    let scale = 1.0 / max(sqrt(norm), 1e-8)
    return v.map { $0 * scale }
}
