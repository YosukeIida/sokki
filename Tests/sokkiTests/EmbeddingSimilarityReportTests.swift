import Testing
@testable import SokkiKit

/// TASK-27: 類似度行列（話者内 min/mean・話者間 max/mean）を算出する純粋ロジックのテスト。
/// 合成 embedding でコサイン類似度を厳密に制御し、同一話者/他話者の分布が正しく集計されることを確認する。
@Suite("EmbeddingSimilarityReport")
struct EmbeddingSimilarityReportTests {

    @Test("同一話者内は高い類似度・話者間は低い類似度として集計される")
    func distinguishesIntraFromInter() throws {
        // S1: 互いに 0.95 類似する2発話 / S2: S1 とは 0.30 しか類似しない発話1件を追加
        let pair = makeEmbeddingPair(cosineSimilarity: 0.95)
        let interPair = makeEmbeddingPair(cosineSimilarity: 0.30)

        let report = EmbeddingSimilarityReport.compute(groupedEmbeddings: [
            "S1": [pair.a, pair.b],
            "S2": [interPair.b],
        ])

        #expect(report.intraSpeakerStats.count == 1)
        let s1 = try #require(report.intraSpeakerStats.first)
        #expect(s1.speakerID == "S1")
        #expect(s1.sampleCount == 2)
        #expect(abs(s1.minSimilarity - 0.95) < 1e-4)
        #expect(abs(s1.meanSimilarity - 0.95) < 1e-4)

        #expect(report.interSpeakerStats.count == 1)
        let pairStat = try #require(report.interSpeakerStats.first)
        #expect(Set([pairStat.speakerA, pairStat.speakerB]) == Set(["S1", "S2"]))
        // interPair.b と S1 の a / b それぞれの類似度は 0.30 / 約0.5829（幾何学的に一意に定まる）。
        #expect(abs(pairStat.maxSimilarity - 0.5829) < 1e-3)
        #expect(abs(pairStat.meanSimilarity - 0.4415) < 1e-3)
    }

    @Test("サンプルが1件のみの話者は話者内統計から除外される")
    func excludesSingleSampleSpeakerFromIntraStats() {
        let pair = makeEmbeddingPair(cosineSimilarity: 0.9)

        let report = EmbeddingSimilarityReport.compute(groupedEmbeddings: [
            "S1": [pair.a],
            "S2": [pair.b],
        ])

        #expect(report.intraSpeakerStats.isEmpty)
        #expect(report.interSpeakerStats.count == 1)
    }

    @Test("話者が1人のみの場合は話者間統計が空になる")
    func singleSpeakerHasNoInterStats() {
        let pair = makeEmbeddingPair(cosineSimilarity: 0.9)

        let report = EmbeddingSimilarityReport.compute(groupedEmbeddings: [
            "S1": [pair.a, pair.b]
        ])

        #expect(report.interSpeakerStats.isEmpty)
        #expect(report.intraSpeakerStats.count == 1)
    }

    @Test("embedding を持たないセグメントは DiarizationResult からの集計で無視される")
    func ignoresSegmentsWithoutEmbedding() {
        let pair = makeEmbeddingPair(cosineSimilarity: 0.9)
        let result = DiarizationResult(
            segments: [
                DiarizationSegment(start: 0, end: 1, speakerID: "S1", embedding: pair.a),
                DiarizationSegment(start: 1, end: 2, speakerID: "S1", embedding: nil),
                DiarizationSegment(start: 2, end: 3, speakerID: "S2", embedding: pair.b),
            ],
            numberOfSpeakers: 2
        )

        let report = EmbeddingSimilarityReport.compute(from: result)

        #expect(report.intraSpeakerStats.isEmpty)  // S1 は embedding 付きが1件のみ
        #expect(report.interSpeakerStats.count == 1)
    }

    @Test("formatted() は話者IDと数値を含むテキストを生成する")
    func formattedIncludesKeyInformation() {
        let pair = makeEmbeddingPair(cosineSimilarity: 0.95)
        let report = EmbeddingSimilarityReport.compute(groupedEmbeddings: [
            "S1": [pair.a, pair.b]
        ])

        let text = report.formatted()
        #expect(text.contains("S1"))
        #expect(text.contains("話者内類似度"))
        #expect(text.contains("話者間類似度"))
    }
}
