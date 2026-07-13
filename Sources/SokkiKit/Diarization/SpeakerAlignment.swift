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
        /// 未割当（結果に含めない）のままにする。**既定**。
        case leaveUnassigned
        /// 端点ギャップ距離で最も近い diarization セグメントの話者を割り当てる（WhisperX とは異なる
        /// 派生仕様。`assign` の doc コメント「`.fillNearest` の最近傍規則」を参照）。
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
    /// ## `.fillNearest` の最近傍規則（WhisperX とは異なる派生仕様）
    /// 「文字起こし区間と diarization 区間の時間ギャップ（区間の端どうしの距離。内包・交差時は 0）」が
    /// 最小の区間の話者を選ぶ。ギャップ同値なら開始時刻が早い区間、それも同値なら speakerID 昇順。
    ///
    /// WhisperX は区間**中点**どうしの距離で最近傍を決めるが、本実装は**端点**ギャップ距離を用いる
    /// **派生仕様**であり、両者は挙動が異なりうる。例: 文字起こし [10,11]、話者 A [0,9]、話者 B [12,13]
    /// のとき、本実装は端点ギャップ（A・B とも 1.0）が同値のため開始時刻が早い A を選ぶが、WhisperX は
    /// 中点距離（A: |10.5-4.5|=6.0、B: |10.5-12.5|=2.0）で B を選ぶ。端点距離は長短の異なる区間に
    /// 頑健なため採用する（`.fillNearest` は既定ではないオプション経路）。
    ///
    /// ## 無効区間の扱い
    /// `start > end`・NaN・無限を含む区間は無効として無視する（文字起こし側は未割当のまま、
    /// diarization 側は交差・最近傍のどちらの計算からも除外）。`start == end`（ゼロ幅・端点接触）は
    /// 有効だが交差 0 のため通常は未割当になる（`.fillNearest` ではギャップ 0 として最近傍になりうる）。
    public static func assign(
        transcriptionIntervals: [Interval],
        diarizationSegments: [DiarizationSegment],
        unmatchedPolicy: UnmatchedPolicy = .leaveUnassigned
    ) -> [Int: String] {
        // 無効な diarization 区間（逆転・NaN・無限）は交差・最近傍の計算対象から除外する。
        let validDiarization = diarizationSegments.filter {
            isValidInterval(start: $0.start, end: $0.end)
        }
        guard !validDiarization.isEmpty else { return [:] }

        var result: [Int: String] = [:]
        for (index, interval) in transcriptionIntervals.enumerated() {
            // 無効な文字起こし区間は未割当のまま（結果に含めない）。
            guard isValidInterval(start: interval.start, end: interval.end) else { continue }
            if let speaker = bestSpeakerByTotalOverlap(for: interval, in: validDiarization) {
                result[index] = speaker
            } else if case .fillNearest = unmatchedPolicy,
                      let nearest = nearestSpeaker(for: interval, in: validDiarization) {
                result[index] = nearest
            }
        }
        return result
    }

    // MARK: - Private

    /// 区間が有効か（有限かつ `start <= end`）。`start == end`（ゼロ幅）は有効とする。
    private static func isValidInterval(start: TimeInterval, end: TimeInterval) -> Bool {
        start.isFinite && end.isFinite && start <= end
    }

    /// 加算順に由来する浮動小数ノイズを吸収するため、交差合計をナノ秒（1e-9 秒）粒度に丸める。
    /// 丸め後は完全一致で比較でき、タイブレーク比較が推移律を満たす（strict weak ordering を保つ）。
    private static func quantizedOverlap(_ value: Double) -> Double {
        let scale = 1e9
        return (value * scale).rounded() / scale
    }

    /// 話者ごとの交差合計を集計し、最大の話者を（タイブレーク規則に従って）返す。交差ゼロなら nil。
    private static func bestSpeakerByTotalOverlap(
        for interval: Interval,
        in diarizationSegments: [DiarizationSegment]
    ) -> String? {
        struct Accumulator {
            var totalOverlap: Double
            var earliestOverlapStart: TimeInterval
        }

        // 入力順に依存せず合計が一意に決まるよう、diarization を正規順（start → end → speakerID）で
        // 走査してから話者ごとに加算する。これにより「並び替えで勝者不変」が保証される。
        let sorted = diarizationSegments.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end < b.end }
            return a.speakerID < b.speakerID
        }

        var bySpeaker: [String: Accumulator] = [:]
        for d in sorted {
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
        // 交差合計は量子化して比較し、加算順の FP ノイズでタイブレークが乱れないようにする。
        return bySpeaker.max { lhs, rhs in
            let lhsOverlap = quantizedOverlap(lhs.value.totalOverlap)
            let rhsOverlap = quantizedOverlap(rhs.value.totalOverlap)
            if lhsOverlap != rhsOverlap {
                return lhsOverlap < rhsOverlap
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
