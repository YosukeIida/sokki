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
}
