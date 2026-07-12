import Foundation
import Testing
@testable import SokkiKit

/// 日本語 DER・声紋閾値の**実測**用テスト（ローカル専用 / TASK-31）。
///
/// CI や通常の `swift test` では環境変数が未設定なので `.enabled(if:)` により skip される。
/// 実測手順は `docs/diarization-benchmark.md` を参照。
///
/// ## 実行方法
/// ```
/// SOKKI_DER_AUDIO=/path/to/audio.wav \
/// SOKKI_DER_REFERENCE=/path/to/reference.rttm \
/// swift test --filter DiarizationBenchmark
/// ```
/// - `SOKKI_DER_AUDIO`      : 計測対象の音声ファイル（wav / m4a など AVAudioFile が読める形式）
/// - `SOKKI_DER_REFERENCE`  : 正解ラベル（`.rttm` なら RTTM、それ以外は TSV `start<TAB>end<TAB>speaker`）
/// - `SOKKI_DER_COLLAR`     : （任意）collar 秒。未指定なら 0.0。CALLHOME 慣習に合わせるなら 0.25
@Suite("DiarizationBenchmark")
struct DiarizationBenchmarkTests {

    /// 実測に必要な環境変数が両方揃っているときだけ有効化する。
    static var isConfigured: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["SOKKI_DER_AUDIO"] != nil && env["SOKKI_DER_REFERENCE"] != nil
    }

    @Test("実音声で DER を計測し内訳と閾値材料を出力する", .enabled(if: DiarizationBenchmarkTests.isConfigured))
    func measureDER() async throws {
        let env = ProcessInfo.processInfo.environment
        let audioPath = try #require(env["SOKKI_DER_AUDIO"])
        let referencePath = try #require(env["SOKKI_DER_REFERENCE"])
        let collar = env["SOKKI_DER_COLLAR"].flatMap(Double.init) ?? 0.0

        // 1. 音声を 16kHz mono へ復号。
        let samples = try AudioFileReader.readMonoSamples(url: URL(fileURLWithPath: audioPath))
        #expect(!samples.isEmpty, "音声サンプルが空です: \(audioPath)")

        // 2. FluidAudio で diarize。
        let engine = FluidAudioEngine()
        try await engine.prepare()
        let result = try await engine.diarize(audioArray: samples)

        // 3. 仮説区間へ変換。
        let hypothesis = result.segments.map {
            DiarizationInterval(start: $0.start, end: $0.end, speaker: $0.speakerID)
        }

        // 4. 正解ラベルをパース。
        let reference = try RTTMParser.parse(contentsOf: URL(fileURLWithPath: referencePath))
        #expect(!reference.isEmpty, "リファレンスが空です: \(referencePath)")

        // 5. DER を計算。
        let der = DERCalculator.computeDER(reference: reference, hypothesis: hypothesis, collar: collar)

        // 6. レポート出力。
        printReport(
            audioPath: audioPath,
            referencePath: referencePath,
            collar: collar,
            reference: reference,
            hypothesis: hypothesis,
            result: result,
            der: der
        )

        // 実測なので値のアサートはしない（値の解釈は docs/diarization-benchmark.md）。
        // ただし計算が破綻していないことだけ最低限確認する。
        #expect(der.der >= 0)
    }

    // MARK: - レポート出力

    private func printReport(
        audioPath: String,
        referencePath: String,
        collar: Double,
        reference: [DiarizationInterval],
        hypothesis: [DiarizationInterval],
        result: DiarizationResult,
        der: DERResult
    ) {
        func pct(_ x: Double) -> String { String(format: "%.2f%%", x * 100) }
        func sec(_ x: Double) -> String { String(format: "%.2fs", x) }

        var lines: [String] = []
        lines.append("================ DER Benchmark (TASK-31) ================")
        lines.append("audio      : \(audioPath)")
        lines.append("reference  : \(referencePath)")
        lines.append("collar     : \(sec(collar))")
        lines.append("ref segments: \(reference.count) / hyp segments: \(hypothesis.count)")
        lines.append("ref speakers: \(Set(reference.map(\.speaker)).count) / hyp speakers: \(result.numberOfSpeakers)")
        lines.append("--------------------------------------------------------")
        lines.append("DER        : \(pct(der.der))")
        lines.append("  missed   : \(pct(der.missedRate))  (\(sec(der.missedDuration)))")
        lines.append("  falseAlrm: \(pct(der.falseAlarmRate))  (\(sec(der.falseAlarmDuration)))")
        lines.append("  confusion: \(pct(der.confusionRate))  (\(sec(der.confusionDuration)))")
        lines.append("  scored ref total: \(sec(der.totalReferenceDuration))")
        lines.append("speaker map (hyp -> ref): \(der.speakerMapping)")
        lines.append("--------------------------------------------------------")
        lines.append("参考ベンチ: Sortformer v2 = 12.70% / Pyannote community-1 = 28.80%")
        lines.append("           DiariZen = 15.60%（arXiv 2509.26177）")
        lines.append("--------------------------------------------------------")

        // 声紋閾値 0.82 の材料: 話者セントロイド間のコサイン類似度。
        // 別話者どうしが 0.82 を下回る（=閾値で分離できる）ことを実測で確認する材料。
        let similarities = pairwiseCentroidSimilarities(segments: result.segments)
        if similarities.isEmpty {
            lines.append("声紋類似度: embedding が無いため算出不可")
        } else {
            lines.append("話者セントロイド間コサイン類似度（別話者ペア / 閾値 0.82 の妥当性材料）:")
            for entry in similarities {
                let flag = entry.similarity >= 0.82 ? "  ⚠ >=0.82（別話者だが閾値超過）" : ""
                lines.append(String(format: "  %@ vs %@ : %.4f%@", entry.a, entry.b, entry.similarity, flag))
            }
        }
        lines.append("========================================================")

        print(lines.joined(separator: "\n"))
    }

    private struct SimilarityEntry { let a: String; let b: String; let similarity: Float }

    /// 各話者の embedding 平均（セントロイド）を作り、別話者ペア間のコサイン類似度を返す。
    private func pairwiseCentroidSimilarities(segments: [DiarizationSegment]) -> [SimilarityEntry] {
        var sums: [String: [Float]] = [:]
        var counts: [String: Int] = [:]
        for seg in segments {
            guard let emb = seg.embedding else { continue }
            if var acc = sums[seg.speakerID] {
                for i in 0..<min(acc.count, emb.count) { acc[i] += emb[i] }
                sums[seg.speakerID] = acc
            } else {
                sums[seg.speakerID] = emb
            }
            counts[seg.speakerID, default: 0] += 1
        }
        let centroids: [String: [Float]] = sums.mapValues { l2Normalize($0) }
        let matcher = EmbeddingMatcher()
        let speakers = centroids.keys.sorted()
        var entries: [SimilarityEntry] = []
        for i in 0..<speakers.count {
            for j in (i + 1)..<speakers.count {
                let a = speakers[i], b = speakers[j]
                guard let ea = centroids[a], let eb = centroids[b] else { continue }
                entries.append(SimilarityEntry(a: a, b: b, similarity: matcher.cosineSimilarity(ea, eb)))
            }
        }
        return entries
    }
}
