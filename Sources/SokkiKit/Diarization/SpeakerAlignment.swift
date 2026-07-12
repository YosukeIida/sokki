import Foundation

/// 文字起こしセグメントと diarization セグメントを時間軸でアラインメントし、各文字起こし
/// セグメントへ話者ラベル（speakerID）を割り当てる純粋関数（P3 / TASK-26）。
///
/// アルゴリズムは WhisperX の `assign_word_speakers`（diarize.py）に倣う。
/// 各文字起こしセグメントについて、diarization セグメントとの**交差時間を話者ごとに合計**し、
/// 合計交差が最大の話者を採用する。
///
/// これは TASK-25 の簡易実装（「単一の最大交差 diarization セグメントの話者」を採用）より
/// 頑健である。例として、ある文字起こしセグメントに対し
///   - 話者 A: 1 区間だけ交差（交差 4.0）
///   - 話者 B: 2 区間が交差（交差 3.0 + 3.0 = 6.0）
/// のとき、単一最大交差では A（4.0 > 各 3.0）が選ばれるが、合計交差では B（6.0 > 4.0）が選ばれる。
/// 話者が細切れに発話するケースで合計交差方式のほうが実態に合う。
///
/// 状態を持たない `enum`（名前空間）として実装し、SwiftData や actor から独立してテストできる。
public enum SpeakerAlignment {

    /// 文字起こしセグメントの時間区間。半開区間 [start, end) として扱う。
    public struct Interval: Sendable, Equatable {
        public let start: TimeInterval
        public let end: TimeInterval

        public init(start: TimeInterval, end: TimeInterval) {
            self.start = start
            self.end = end
        }
    }

    /// どの diarization 区間とも交差しない（交差ゼロの）文字起こしセグメントの扱い。
    public enum UnmatchedPolicy: Sendable {
        /// 未割当（結果に含めない）のままにする。WhisperX の `fill_nearest=False` 相当。**既定**。
        case leaveUnassigned
        /// 最近傍の diarization セグメントの話者を割り当てる。WhisperX の `fill_nearest=True` 相当。
        case fillNearest
    }

    /// 各文字起こしセグメントに話者 ID を割り当てる。
    ///
    /// - Parameters:
    ///   - transcriptionIntervals: 文字起こしセグメントの時間区間。**入力順を保持**し、返り値の
    ///     index はこの配列の index に対応する。
    ///   - diarizationSegments: diarization セグメント。
    ///   - unmatchedPolicy: 交差ゼロ時の扱い（既定 `.leaveUnassigned`）。
    /// - Returns: `transcriptionIntervals` の index → speakerID。割り当てられなかった index は
    ///   結果に含めない（キーが存在しない）。
    ///
    /// ## タイブレーク規則（交差合計が同値の話者が複数ある場合）
    /// 1. **当該セグメントと交差する diarization 区間のうち最も早い開始時刻**が小さい話者を選ぶ。
    /// 2. それも同値なら speakerID の昇順（辞書順）で小さい話者を選ぶ。
    ///
    /// speakerID は一意なので必ず一意に決まり、`diarizationSegments` の順序に依存しない決定的な出力になる。
    ///
    /// ## `.fillNearest` の最近傍規則
    /// 「文字起こし区間と diarization 区間の時間ギャップ（区間の端どうしの距離。内包・交差時は 0）」が
    /// 最小の区間の話者を選ぶ。ギャップ同値なら開始時刻が早い区間、それも同値なら speakerID 昇順。
    /// WhisperX は区間中点どうしの距離を使うが、端どうしの距離のほうが長短の異なる区間で頑健なため
    /// こちらを採用する（`.fillNearest` は既定ではないオプション経路）。
    public static func assign(
        transcriptionIntervals: [Interval],
        diarizationSegments: [DiarizationSegment],
        unmatchedPolicy: UnmatchedPolicy = .leaveUnassigned
    ) -> [Int: String] {
        guard !diarizationSegments.isEmpty else { return [:] }

        var result: [Int: String] = [:]
        for (index, interval) in transcriptionIntervals.enumerated() {
            if let speaker = bestSpeakerByTotalOverlap(for: interval, in: diarizationSegments) {
                result[index] = speaker
            } else if case .fillNearest = unmatchedPolicy,
                      let nearest = nearestSpeaker(for: interval, in: diarizationSegments) {
                result[index] = nearest
            }
        }
        return result
    }

    // MARK: - Private

    /// 話者ごとの交差合計を集計し、最大の話者を（タイブレーク規則に従って）返す。交差ゼロなら nil。
    private static func bestSpeakerByTotalOverlap(
        for interval: Interval,
        in diarizationSegments: [DiarizationSegment]
    ) -> String? {
        struct Accumulator {
            var totalOverlap: Double
            var earliestOverlapStart: TimeInterval
        }

        var bySpeaker: [String: Accumulator] = [:]
        for d in diarizationSegments {
            let overlap = min(interval.end, d.end) - max(interval.start, d.start)
            guard overlap > 0 else { continue }
            if var acc = bySpeaker[d.speakerID] {
                acc.totalOverlap += overlap
                acc.earliestOverlapStart = min(acc.earliestOverlapStart, d.start)
                bySpeaker[d.speakerID] = acc
            } else {
                bySpeaker[d.speakerID] = Accumulator(totalOverlap: overlap, earliestOverlapStart: d.start)
            }
        }

        guard !bySpeaker.isEmpty else { return nil }

        // max(by:) は最も「大きい」要素を返す。ここでは lhs が rhs より劣後（順序が前）なら true。
        return bySpeaker.max { lhs, rhs in
            if lhs.value.totalOverlap != rhs.value.totalOverlap {
                return lhs.value.totalOverlap < rhs.value.totalOverlap
            }
            if lhs.value.earliestOverlapStart != rhs.value.earliestOverlapStart {
                return lhs.value.earliestOverlapStart > rhs.value.earliestOverlapStart
            }
            return lhs.key > rhs.key
        }?.key
    }

    /// 文字起こし区間に最も近い diarization 区間の話者を返す（`.fillNearest` 用）。
    private static func nearestSpeaker(
        for interval: Interval,
        in diarizationSegments: [DiarizationSegment]
    ) -> String? {
        var best: (gap: Double, start: TimeInterval, speakerID: String)?
        for d in diarizationSegments {
            let gap: Double
            if d.end <= interval.start {
                gap = interval.start - d.end
            } else if d.start >= interval.end {
                gap = d.start - interval.end
            } else {
                gap = 0 // 交差あり（呼び出し側で交差ゼロ時のみ来る想定だが念のため）
            }

            let isBetter: Bool
            if let b = best {
                if gap != b.gap {
                    isBetter = gap < b.gap
                } else if d.start != b.start {
                    isBetter = d.start < b.start
                } else {
                    isBetter = d.speakerID < b.speakerID
                }
            } else {
                isBetter = true
            }
            if isBetter {
                best = (gap: gap, start: d.start, speakerID: d.speakerID)
            }
        }
        return best?.speakerID
    }
}
