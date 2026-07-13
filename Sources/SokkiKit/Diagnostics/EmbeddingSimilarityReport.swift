import Foundation
import os

/// 声紋照合閾値（既定 0.82）の妥当性を実 embedding で検証するための診断ハーネス（TASK-27）。
///
/// diarization 結果に含まれる話者ごとの embedding から、
/// 「同一話者内の類似度分布」と「話者間の類似度分布」を集計する。
/// 利用者は実会話を録音した上で本レポートを（DEBUG ビルドの）ログから確認し、
/// 閾値 0.82 が同一話者内の下限より低く・話者間の上限より高いかを判断できる。
///
/// UI には出さない（過剰なため）。`TranscriptionPipeline` から DEBUG ビルド限定で
/// Logger（category "diagnostics"）へ INFO 出力するフックとしてのみ使う。
///
/// ⚠️ 測定範囲の限界（レビュー指摘・TASK-27）:
/// 本レポートは **単一の diarization 実行（= 1回の録音）内**の生セグメント embedding 同士の
/// 類似度のみを見る。一方、実際に閾値 0.82 が適用されるのは
/// `SpeakerProfileStore.resolveProfiles` が算出する「1セッション分の平均・正規化ベクトル」と
/// 「過去セッションの EMA 更新済みプロファイル embedding」との比較であり、両者は別物である。
/// そのため、本レポートの「話者内類似度」が高い（例: min > 0.82）ことは、
/// **同一セッション内での diarization クラスタリングの安定性**を示すのみで、
/// 「別録音（別日・別マイク環境等）でも同一人物として正しく再認識されるか」という
/// TASK-27 の本題（録音間の再現性）を直接検証するものではない。
/// 録音間の再現性を検証するには、同一話者が登場する複数回の録音を行い、
/// それぞれのログの話者内平均を目視で比較する（本ハーネスは自動相関までは行わない）。
struct EmbeddingSimilarityReport {

    struct IntraSpeakerStat: Equatable {
        let speakerID: String
        let sampleCount: Int
        let minSimilarity: Float
        let meanSimilarity: Float
    }

    struct InterSpeakerStat: Equatable {
        let speakerA: String
        let speakerB: String
        let maxSimilarity: Float
        let meanSimilarity: Float
    }

    let intraSpeakerStats: [IntraSpeakerStat]
    let interSpeakerStats: [InterSpeakerStat]

    private static let logger = Logger(subsystem: "com.sokki.app", category: "diagnostics")

    /// 話者ID → embedding 群 から類似度分布を集計する（純粋関数）。
    ///
    /// - 話者内統計はペアが組める（サンプル数 2 以上の）話者のみを対象にする。
    /// - 話者間統計は embedding を1件以上持つ話者の全ペアを対象にする。
    static func compute(groupedEmbeddings: [String: [[Float]]]) -> EmbeddingSimilarityReport {
        let matcher = EmbeddingMatcher()
        let speakerIDs = groupedEmbeddings.keys.sorted()

        var intra: [IntraSpeakerStat] = []
        for speakerID in speakerIDs {
            let embeddings = groupedEmbeddings[speakerID] ?? []
            guard embeddings.count >= 2 else { continue }

            var similarities: [Float] = []
            for i in 0..<embeddings.count {
                for j in (i + 1)..<embeddings.count {
                    similarities.append(matcher.cosineSimilarity(embeddings[i], embeddings[j]))
                }
            }
            guard !similarities.isEmpty else { continue }
            intra.append(IntraSpeakerStat(
                speakerID: speakerID,
                sampleCount: embeddings.count,
                minSimilarity: similarities.min() ?? 0,
                meanSimilarity: similarities.reduce(0, +) / Float(similarities.count)
            ))
        }

        var inter: [InterSpeakerStat] = []
        for i in 0..<speakerIDs.count {
            for j in (i + 1)..<speakerIDs.count {
                let speakerA = speakerIDs[i]
                let speakerB = speakerIDs[j]
                let embeddingsA = groupedEmbeddings[speakerA] ?? []
                let embeddingsB = groupedEmbeddings[speakerB] ?? []
                guard !embeddingsA.isEmpty, !embeddingsB.isEmpty else { continue }

                var similarities: [Float] = []
                for a in embeddingsA {
                    for b in embeddingsB {
                        similarities.append(matcher.cosineSimilarity(a, b))
                    }
                }
                guard !similarities.isEmpty else { continue }
                inter.append(InterSpeakerStat(
                    speakerA: speakerA,
                    speakerB: speakerB,
                    maxSimilarity: similarities.max() ?? 0,
                    meanSimilarity: similarities.reduce(0, +) / Float(similarities.count)
                ))
            }
        }

        return EmbeddingSimilarityReport(intraSpeakerStats: intra, interSpeakerStats: inter)
    }

    /// diarization 結果（embedding 付きセグメント）から話者ID → embedding 群を組み立てて集計する。
    /// embedding を持たないセグメントは無視する。
    static func compute(from result: DiarizationResult) -> EmbeddingSimilarityReport {
        var grouped: [String: [[Float]]] = [:]
        for segment in result.segments {
            guard let embedding = segment.embedding else { continue }
            grouped[segment.speakerID, default: []].append(embedding)
        }
        return compute(groupedEmbeddings: grouped)
    }

    /// 人が読めるテキストレポートに整形する。
    func formatted() -> String {
        var lines: [String] = []
        lines.append("=== 声紋照合 類似度レポート（閾値検証用 / TASK-27）===")
        lines.append("※本レポートは今回の録音1回分のみの集計です。プロファイル照合は録音間の")
        lines.append("  平均ベクトル同士の比較のため、録音間の再現性は複数回録音し目視で比較してください。")

        lines.append("[話者内類似度]")
        if intraSpeakerStats.isEmpty {
            lines.append("  算出不可（各話者に2発話以上の embedding が必要）")
        } else {
            for stat in intraSpeakerStats {
                lines.append(String(
                    format: "  %@ (n=%d): min=%.4f mean=%.4f",
                    stat.speakerID, stat.sampleCount, stat.minSimilarity, stat.meanSimilarity
                ))
            }
        }

        lines.append("[話者間類似度]")
        if interSpeakerStats.isEmpty {
            lines.append("  算出不可（話者が2人以上必要）")
        } else {
            for stat in interSpeakerStats {
                lines.append(String(
                    format: "  %@-%@: max=%.4f mean=%.4f",
                    stat.speakerA, stat.speakerB, stat.maxSimilarity, stat.meanSimilarity
                ))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Logger（subsystem "com.sokki.app", category "diagnostics"）へ INFO 出力する。
    /// 呼び出し側で `#if DEBUG` により本番ビルドでは呼ばれないようにする想定。
    func log() {
        Self.logger.info("\(self.formatted(), privacy: .public)")
    }
}
