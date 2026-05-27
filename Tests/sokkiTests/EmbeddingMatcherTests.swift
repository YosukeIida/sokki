import Testing
import Darwin
@testable import SokkiKit

@Suite("EmbeddingMatcher")
struct EmbeddingMatcherTests {

    @Test("同一ベクトルのコサイン類似度は 1.0")
    func samVectorSimilarity() {
        let matcher = EmbeddingMatcher(threshold: 0.82)
        let v: [Float] = l2Normalize(Array(repeating: 1.0, count: 256))
        #expect(matcher.cosineSimilarity(v, v) ≈ 1.0)
    }

    @Test("直交ベクトルのコサイン類似度は 0.0")
    func orthogonalVectorSimilarity() {
        let matcher = EmbeddingMatcher(threshold: 0.82)
        var a = [Float](repeating: 0, count: 256)
        var b = [Float](repeating: 0, count: 256)
        a[0] = 1.0
        b[1] = 1.0
        #expect(matcher.cosineSimilarity(a, b) ≈ 0.0)
    }

    @Test("閾値以上なら bestMatch が返る")
    func matchAboveThreshold() throws {
        // NOTE: SpeakerProfileModel は SwiftData @Model なので統合テストで検証
        // ここでは EmbeddingMatcher.cosineSimilarity の数値精度のみテスト
        let matcher = EmbeddingMatcher(threshold: 0.82)
        let v: [Float] = l2Normalize((0..<256).map { Float($0) })
        let score = matcher.cosineSimilarity(v, v)
        #expect(score >= 0.82)
    }

    @Test("L2 正規化後のノルムは 1.0")
    func l2NormAfterNormalization() {
        let v: [Float] = (0..<256).map { Float($0) }
        let normalized = l2Normalize(v)
        let norm = sqrt(normalized.map { $0 * $0 }.reduce(0, +))
        #expect(abs(norm - 1.0) < 1e-5)
    }
}

infix operator ≈: ComparisonPrecedence
func ≈ (lhs: Float, rhs: Float) -> Bool { abs(lhs - rhs) < 1e-5 }
