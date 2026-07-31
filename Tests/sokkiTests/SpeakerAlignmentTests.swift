import Foundation
import Testing
@testable import SokkiKit

/// TASK-26: WhisperX 方式（話者ごとの交差合計が最大）で文字起こしセグメントに話者を割り当てる
/// 純粋関数 `SpeakerAlignment.assign` の網羅テスト。
@Suite("SpeakerAlignment")
struct SpeakerAlignmentTests {

    /// speakerID / start / end から DiarizationSegment を作る（embedding は本アルゴリズムでは未使用）。
    private func dia(_ speakerID: String, _ start: Double, _ end: Double) -> DiarizationSegment {
        DiarizationSegment(start: start, end: end, speakerID: speakerID, embedding: nil)
    }

    private func interval(_ start: Double, _ end: Double) -> SpeakerAlignment.Interval {
        SpeakerAlignment.Interval(start: start, end: end)
    }

    @Test("単一話者に完全に含まれるセグメントはその話者に割り当てられる")
    func singleSpeakerFullCoverage() {
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(1, 4)],
            diarizationSegments: [dia("S1", 0, 10)]
        )
        #expect(assignment == [0: "S1"])
    }

    @Test("交差合計が単一最大交差と異なるケースでは合計交差の話者が選ばれる（TASK-25 との差）")
    func totalOverlapDiffersFromSingleMaxOverlap() {
        // 文字起こし [0,10]:
        //   S1 は 1 区間のみ交差 4.0（単一最大交差）
        //   S2 は 2 区間で交差 3.0 + 3.0 = 6.0（合計最大）
        // TASK-25 の単一最大交差方式なら S1（4.0 > 各 3.0）だが、WhisperX 方式では S2。
        let diarization = [
            dia("S1", 0, 4),
            dia("S2", 4, 7),
            dia("S2", 7, 10),
        ]
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 10)],
            diarizationSegments: diarization
        )
        #expect(assignment == [0: "S2"])
    }

    @Test("複数セグメントがそれぞれ最大合計交差の話者に割り当てられる")
    func multipleSegments() {
        let diarization = [dia("S1", 0, 10), dia("S2", 10, 20)]
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(1, 4), interval(9, 16)],
            diarizationSegments: diarization
        )
        // seg0 は S1 に完全内包 / seg1 は S1 と 1.0・S2 と 6.0 → S2
        #expect(assignment == [0: "S1", 1: "S2"])
    }

    @Test("交差ゼロは既定（leaveUnassigned）で未割当")
    func zeroOverlapLeavesUnassigned() {
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(100, 110)],
            diarizationSegments: [dia("S1", 0, 10)]
        )
        #expect(assignment.isEmpty)
    }

    @Test("交差ゼロは fillNearest で最近傍の話者に割り当てられる")
    func zeroOverlapFillNearest() {
        // 文字起こし [100,110]: S1 は [0,10]（ギャップ 90）、S2 は [95,99]（ギャップ 1）→ S2
        let diarization = [dia("S1", 0, 10), dia("S2", 95, 99)]
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(100, 110)],
            diarizationSegments: diarization,
            unmatchedPolicy: .fillNearest
        )
        #expect(assignment == [0: "S2"])
    }

    @Test("交差ありのセグメントは fillNearest でも通常の合計交差ロジックが優先される")
    func fillNearestDoesNotOverrideOverlap() {
        let diarization = [dia("S1", 0, 6), dia("S2", 100, 110)]
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 5)],
            diarizationSegments: diarization,
            unmatchedPolicy: .fillNearest
        )
        #expect(assignment == [0: "S1"])
    }

    @Test("交差合計が同値なら開始時刻が早い話者が選ばれる")
    func tieBreakByEarliestStart() {
        // 文字起こし [0,10]: S1 [0,5] 交差5.0 / S2 [5,10] 交差5.0 → 同値。開始が早い S1。
        let diarization = [dia("S1", 0, 5), dia("S2", 5, 10)]
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 10)],
            diarizationSegments: diarization
        )
        #expect(assignment == [0: "S1"])
    }

    @Test("交差合計・開始時刻が同値なら speakerID 昇順で選ばれ、順序に依存しない")
    func tieBreakBySpeakerIDIsOrderIndependent() {
        // 同一区間 [0,5] の 2 話者（合計交差 5.0・開始 0 とも同値）→ speakerID 昇順で "A"。
        let forward = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 5)],
            diarizationSegments: [dia("A", 0, 5), dia("B", 0, 5)]
        )
        let reversed = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 5)],
            diarizationSegments: [dia("B", 0, 5), dia("A", 0, 5)]
        )
        #expect(forward == [0: "A"])
        #expect(reversed == [0: "A"])
    }

    @Test("空の文字起こし入力は空の結果を返す")
    func emptyTranscriptionInput() {
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [],
            diarizationSegments: [dia("S1", 0, 10)]
        )
        #expect(assignment.isEmpty)
    }

    @Test("空の diarization 入力は空の結果を返す")
    func emptyDiarizationInput() {
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 10)],
            diarizationSegments: []
        )
        #expect(assignment.isEmpty)
    }

    @Test("空の diarization 入力は fillNearest でも空の結果を返す")
    func emptyDiarizationInputFillNearest() {
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 10)],
            diarizationSegments: [],
            unmatchedPolicy: .fillNearest
        )
        #expect(assignment.isEmpty)
    }

    // MARK: - fillNearest（端点ギャップ・WhisperX との差異）

    @Test("fillNearest は端点ギャップ距離を使う（WhisperX の中点距離とは異なる派生仕様）")
    func fillNearestUsesEndpointGapNotMidpoint() {
        // 文字起こし [10,11]: A [0,9] の端点ギャップ 1.0、B [12,13] の端点ギャップ 1.0 → 同値。
        // 開始時刻が早い A を選ぶ。WhisperX は中点距離（A:|10.5-4.5|=6.0, B:|10.5-12.5|=2.0）で
        // B を選ぶため、両者の挙動は異なる（回帰固定）。
        let diarization = [dia("A", 0, 9), dia("B", 12, 13)]
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(10, 11)],
            diarizationSegments: diarization,
            unmatchedPolicy: .fillNearest
        )
        #expect(assignment == [0: "A"])
    }

    // MARK: - 数値決定性（加算順非依存）

    @Test("交差合計が同値のとき加算順に依存せず最早開始の話者が選ばれる")
    func summedOverlapTieIsOrderIndependent() {
        // 文字起こし [0,10]:
        //   A: [2,4]+[6,8] = 2.0+2.0 = 4.0（最早開始 2）
        //   B: [0,2]+[8,10] = 2.0+2.0 = 4.0（最早開始 0）
        // 合計同値 → 最早開始が小さい B。diarization の並び順が変わっても同一結果になること。
        let forward = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 10)],
            diarizationSegments: [dia("A", 2, 4), dia("A", 6, 8), dia("B", 0, 2), dia("B", 8, 10)]
        )
        let reversed = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 10)],
            diarizationSegments: [dia("B", 8, 10), dia("B", 0, 2), dia("A", 6, 8), dia("A", 2, 4)]
        )
        #expect(forward == [0: "B"])
        #expect(reversed == [0: "B"])
    }

    // MARK: - 無効区間

    @Test("逆転した文字起こし区間（start > end）は未割当")
    func reversedTranscriptionIntervalIsUnassigned() {
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(10, 5)],
            diarizationSegments: [dia("S1", 0, 20)]
        )
        #expect(assignment.isEmpty)
    }

    @Test("逆転・非有限の diarization 区間は無視され、有効区間のみで割り当てる")
    func invalidDiarizationSegmentsAreIgnored() {
        let diarization = [
            dia("Sbad", 8, 2),        // 逆転 → 無視
            dia("Snan", .nan, 5),     // NaN → 無視
            dia("S1", 0, 10),         // 有効
        ]
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(1, 4)],
            diarizationSegments: diarization
        )
        #expect(assignment == [0: "S1"])
    }

    @Test("全ての diarization 区間が無効なら fillNearest でも空の結果を返す")
    func allInvalidDiarizationYieldsEmpty() {
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(0, 10)],
            diarizationSegments: [dia("Sbad", 5, 1), dia("Sinf", 0, .infinity)],
            unmatchedPolicy: .fillNearest
        )
        #expect(assignment.isEmpty)
    }

    // MARK: - 接触・ゼロ幅

    @Test("端点接触のみ（交差ゼロ）は未割当")
    func touchingOnlyIsUnassigned() {
        // 文字起こし [10,20] と diarization [0,10] は境界 10 で接触するのみ（交差 0）。
        let assignment = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(10, 20)],
            diarizationSegments: [dia("S1", 0, 10)]
        )
        #expect(assignment.isEmpty)
    }

    @Test("ゼロ幅の文字起こし区間は交差ゼロで未割当・fillNearest ではギャップ0で最近傍")
    func zeroWidthTranscriptionInterval() {
        // ゼロ幅 [5,5] は内包する話者があっても交差 0。
        let unassigned = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(5, 5)],
            diarizationSegments: [dia("S1", 0, 10)]
        )
        #expect(unassigned.isEmpty)

        let filled = SpeakerAlignment.assign(
            transcriptionIntervals: [interval(5, 5)],
            diarizationSegments: [dia("S1", 0, 10)],
            unmatchedPolicy: .fillNearest
        )
        #expect(filled == [0: "S1"]) // 内包のためギャップ 0 → 最近傍
    }
}
