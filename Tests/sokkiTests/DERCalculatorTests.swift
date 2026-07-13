import Foundation
import Testing
@testable import SokkiKit

@Suite("DERCalculator")
struct DERCalculatorTests {

    private func iv(_ start: Double, _ end: Double, _ speaker: String) -> DiarizationInterval {
        DiarizationInterval(start: start, end: end, speaker: speaker)
    }

    @Test("完全一致は DER 0%")
    func perfectMatch() {
        let ref = [iv(0, 5, "A"), iv(5, 10, "B")]
        // 仮説はラベルが違っても最適マッピングで一致する。
        let hyp = [iv(0, 5, "spk1"), iv(5, 10, "spk2")]
        let r = DERCalculator.computeDER(reference: ref, hypothesis: hyp)
        #expect(abs(r.der) < 1e-9)
        #expect(abs(r.confusionRate) < 1e-9)
        #expect(abs(r.missedRate) < 1e-9)
        #expect(abs(r.falseAlarmRate) < 1e-9)
        #expect(r.totalReferenceDuration == 10)
    }

    @Test("仮説が空なら全ミスで DER 100%")
    func allMissed() {
        let ref = [iv(0, 5, "A"), iv(5, 10, "B")]
        let r = DERCalculator.computeDER(reference: ref, hypothesis: [])
        #expect(abs(r.der - 1.0) < 1e-9)
        #expect(abs(r.missedRate - 1.0) < 1e-9)
        #expect(r.missedDuration == 10)
    }

    @Test("リファレンスが空・仮説ありは誤検出だが率は 0（分母なし）")
    func allFalseAlarmNoDenominator() {
        let r = DERCalculator.computeDER(reference: [], hypothesis: [iv(0, 5, "A")])
        #expect(r.totalReferenceDuration == 0)
        #expect(r.der == 0)
        #expect(r.falseAlarmDuration == 5)
    }

    @Test("片方の話者を丸ごと取り違えると confusion に計上される")
    func partialConfusion() {
        // ref: A[0,10), B[10,20)。hyp: 前半は正しく s1、後半を s1 に取り違え（B に対応する話者なし）。
        let ref = [iv(0, 10, "A"), iv(10, 20, "B")]
        let hyp = [iv(0, 10, "s1"), iv(10, 20, "s1")]
        let r = DERCalculator.computeDER(reference: ref, hypothesis: hyp)
        // 最適マッピングは s1->A（共起 10）。後半 [10,20) は ref=B, sys=s1(→A) で不一致 → confusion 10s。
        #expect(r.confusionDuration == 10)
        #expect(abs(r.confusionRate - 0.5) < 1e-9)
        #expect(abs(r.der - 0.5) < 1e-9)
        #expect(r.speakerMapping["s1"] == "A")
    }

    @Test("見逃しと誤検出が混在するケース")
    func missedAndFalseAlarm() {
        // ref: A[0,10)。hyp: s1[2,8) のみ（両端 2s ずつ見逃し）+ s2[12,14)（ref 無音への誤検出 2s）。
        let ref = [iv(0, 10, "A")]
        let hyp = [iv(2, 8, "s1"), iv(12, 14, "s2")]
        let r = DERCalculator.computeDER(reference: ref, hypothesis: hyp)
        #expect(r.missedDuration == 4)      // [0,2) + [8,10)
        #expect(r.falseAlarmDuration == 2)  // [12,14)
        #expect(r.totalReferenceDuration == 10)
        #expect(abs(r.missedRate - 0.4) < 1e-9)
        #expect(abs(r.falseAlarmRate - 0.2) < 1e-9)
        #expect(abs(r.der - 0.6) < 1e-9)
    }

    @Test("collar はリファレンス境界周辺をスコア対象外にする")
    func collarExcludesBoundaries() {
        // ref: A[0,10)。hyp: s1[0,9)（末尾 1s 見逃し）。
        // collar なしなら missed=1s / total=10s → DER 10%。
        let ref = [iv(0, 10, "A")]
        let hyp = [iv(0, 9, "s1")]

        let noCollar = DERCalculator.computeDER(reference: ref, hypothesis: hyp)
        #expect(abs(noCollar.der - 0.1) < 1e-9)

        // collar=0.5 で境界 0 と 10 の周囲 ±0.5 を除外。見逃し区間 [9,10) のうち [9.5,10) がスコア対象、
        // かつ分母 total も collar 分だけ縮む。境界周辺が除外され誤差が減ることを確認する。
        let withCollar = DERCalculator.computeDER(reference: ref, hypothesis: hyp, collar: 0.5)
        // total: [0.5, 9.5) = 9s。missed: [9, 9.5) = 0.5s。DER = 0.5/9。
        #expect(abs(withCollar.totalReferenceDuration - 9.0) < 1e-9)
        #expect(abs(withCollar.missedDuration - 0.5) < 1e-9)
        #expect(abs(withCollar.der - (0.5 / 9.0)) < 1e-9)
    }

    @Test("話者ラベルの置換で DER は不変（置換不変性）")
    func relabelInvariance() {
        let ref = [iv(0, 10, "A"), iv(10, 20, "B"), iv(20, 30, "A")]
        let hyp = [iv(0, 10, "x"), iv(10, 20, "y"), iv(20, 27, "x")]
        let base = DERCalculator.computeDER(reference: ref, hypothesis: hyp)

        // ref/hyp のラベルを一括置換しても DER は変わらない。
        func relabel(_ ivs: [DiarizationInterval], _ map: [String: String]) -> [DiarizationInterval] {
            ivs.map { iv($0.start, $0.end, map[$0.speaker] ?? $0.speaker) }
        }
        let refR = relabel(ref, ["A": "話者1", "B": "話者2"])
        let hypR = relabel(hyp, ["x": "P", "y": "Q"])
        let relabeled = DERCalculator.computeDER(reference: refR, hypothesis: hypR)

        #expect(abs(base.der - relabeled.der) < 1e-9)
        #expect(abs(base.missedRate - relabeled.missedRate) < 1e-9)
        #expect(abs(base.falseAlarmRate - relabeled.falseAlarmRate) < 1e-9)
        #expect(abs(base.confusionRate - relabeled.confusionRate) < 1e-9)
    }

    @Test("同一話者の重複区間があっても二重計上せず負の confusion を生まない")
    func duplicateSameSpeakerIntervalsDoNotDoubleCount() {
        // hyp に同一話者 s1 の完全に重なる区間が 2 本ある（手動ラベリングの誤り等を想定）。
        // 話者数は「発話中の区間の本数」ではなく「発話中の話者数」なので、重複があっても
        // nRef=1, nSys=1 として扱われるべきで、confusion が負になってはならない。
        let ref = [iv(0, 5, "A")]
        let hyp = [iv(0, 5, "s1"), iv(0, 5, "s1")]
        let r = DERCalculator.computeDER(reference: ref, hypothesis: hyp)
        #expect(r.confusionDuration >= 0)
        #expect(r.falseAlarmDuration >= 0)
        #expect(r.missedDuration >= 0)
        // s1 は A に一致するので DER 0% のはず（重複区間は同一話者の冗長な表現に過ぎない）。
        #expect(abs(r.der) < 1e-9)
    }

    @Test("ref 側の重複区間も二重計上せず missed を誤らせない")
    func duplicateSameSpeakerReferenceIntervalsDoNotDoubleCount() {
        let ref = [iv(0, 5, "A"), iv(0, 5, "A")]
        let hyp = [iv(0, 5, "s1")]
        let r = DERCalculator.computeDER(reference: ref, hypothesis: hyp)
        #expect(r.missedDuration >= 0)
        #expect(abs(r.der) < 1e-9)
        #expect(r.totalReferenceDuration == 5)
    }

    @Test("貪欲マッチングは全体最適を保証しない（既知の受容済み限界を回帰固定する）")
    func greedyMatchingIsNotAlwaysOptimal() {
        // maxExactPermutations を超える病的な話者数のときだけ使われる貪欲退避は、
        // 最適解を保証しない設計上の既知の限界（DERCalculator.swift のドキュメントコメント参照）。
        // 実運用の会議（2〜6 名）ではまず発生しないが、退避が起きた場合の挙動を明示的に固定しておく。
        //
        // 共起行列: A-x=10, A-y=9, B-x=9, B-y=0。
        // 最適解は A->y(9) + B->x(9) = 18。貪欲は最大ペア A->x(10) を先取りし、残りは B->y(0) のみで計 10。
        func weight(ref: String, sys: String) -> TimeInterval {
            switch (ref, sys) {
            case ("A", "x"): return 10
            case ("A", "y"): return 9
            case ("B", "x"): return 9
            case ("B", "y"): return 0
            default: return 0
            }
        }
        let exact = DERCalculator.exactBestMatching(small: ["A", "B"], large: ["x", "y"], weight: weight)
        let greedy = DERCalculator.greedyMatching(small: ["A", "B"], large: ["x", "y"], weight: weight)

        func totalWeight(_ pairs: [(small: String, large: String)]) -> TimeInterval {
            pairs.reduce(0) { $0 + weight(ref: $1.small, sys: $1.large) }
        }

        #expect(totalWeight(exact) == 18)
        #expect(totalWeight(greedy) == 10)
        // 貪欲が全体最適に届かないことそのものを固定する（この差が「貪欲は近似に過ぎない」根拠）。
        #expect(totalWeight(greedy) < totalWeight(exact))
    }

    @Test("最適マッピングは共起最大の割当を選ぶ（話者数が少ないので常に全順列＝最適解を使う経路）")
    func optimalMappingBeatsGreedy() {
        // 貪欲が最初に最大共起ペアを取ると全体最適を外す配置。
        // ref A[0,10), B[10,30)。hyp s1[0,10)+[10,18)（Aと10, Bと8 共起）, s2[18,30)（Bと12 共起）。
        // 貪欲: 最大共起は s1-B(=8)? いや s1-A=10 が最大。s1->A 確定 → s2->B。
        // ここではむしろ「全体最適が一意に決まる」ことと DER を確認する。
        let ref = [iv(0, 10, "A"), iv(10, 30, "B")]
        let hyp = [iv(0, 18, "s1"), iv(18, 30, "s2")]
        let r = DERCalculator.computeDER(reference: ref, hypothesis: hyp)
        // s1: A と 10 共起, B と 8 共起。s2: B と 12 共起。
        // 最適: s1->A(10) + s2->B(12) = 22。代替 s1->B(8)+s2->? = 8。→ s1->A, s2->B。
        #expect(r.speakerMapping["s1"] == "A")
        #expect(r.speakerMapping["s2"] == "B")
        // [10,18) は ref=B, sys=s1(->A) 不一致 → confusion 8s。total=30。
        #expect(r.confusionDuration == 8)
        #expect(abs(r.der - (8.0 / 30.0)) < 1e-9)
    }
}
