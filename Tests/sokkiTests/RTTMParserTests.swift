import Foundation
import Testing
@testable import SokkiKit

@Suite("RTTMParser")
struct RTTMParserTests {

    @Test("標準的な RTTM の SPEAKER 行をパースする")
    func parsesRTTM() throws {
        let rttm = """
        SPEAKER meeting 1 0.000 5.250 <NA> <NA> spk_A <NA> <NA>
        SPEAKER meeting 1 5.250 3.000 <NA> <NA> spk_B <NA> <NA>
        """
        let intervals = try RTTMParser.parseRTTM(rttm)
        #expect(intervals.count == 2)
        #expect(intervals[0].start == 0.0)
        #expect(abs(intervals[0].end - 5.25) < 1e-9)
        #expect(intervals[0].speaker == "spk_A")
        #expect(abs(intervals[1].start - 5.25) < 1e-9)
        #expect(abs(intervals[1].end - 8.25) < 1e-9)
        #expect(intervals[1].speaker == "spk_B")
    }

    @Test("コメント・空行・非 SPEAKER 型行は無視する")
    func ignoresCommentsAndOtherTypes() throws {
        let rttm = """
        ;; これはコメント

        SPKR-INFO meeting 1 <NA> <NA> <NA> unknown spk_A <NA> <NA>
        SPEAKER meeting 1 1.0 2.0 <NA> <NA> spk_A <NA> <NA>
        """
        let intervals = try RTTMParser.parseRTTM(rttm)
        #expect(intervals.count == 1)
        #expect(intervals[0].speaker == "spk_A")
        #expect(intervals[0].start == 1.0)
        #expect(intervals[0].end == 3.0)
    }

    @Test("数値が壊れた RTTM 行は invalidNumber を投げる")
    func rttmInvalidNumber() {
        let rttm = "SPEAKER meeting 1 x.y 2.0 <NA> <NA> spk_A <NA> <NA>"
        #expect(throws: RTTMParser.ParseError.self) {
            _ = try RTTMParser.parseRTTM(rttm)
        }
    }

    @Test("列不足の SPEAKER 行は malformedLine を投げる")
    func rttmMalformed() {
        let rttm = "SPEAKER meeting 1 0.0 2.0"
        #expect(throws: RTTMParser.ParseError.self) {
            _ = try RTTMParser.parseRTTM(rttm)
        }
    }

    @Test("Audacity 互換 TSV（start\\tend\\tspeaker）をパースする")
    func parsesTSV() throws {
        let tsv = "0.000000\t5.250000\tspk_A\n5.250000\t8.250000\tspk_B\n"
        let intervals = try RTTMParser.parseTSV(tsv)
        #expect(intervals.count == 2)
        #expect(intervals[0].start == 0.0)
        #expect(abs(intervals[0].end - 5.25) < 1e-9)
        #expect(intervals[0].speaker == "spk_A")
        #expect(intervals[1].speaker == "spk_B")
    }

    @Test("TSV のコメント行・空行は無視し、話者ラベル中の空白も保持する")
    func tsvCommentsAndLabelSpaces() throws {
        let tsv = """
        # header
        0.0\t2.0\tSpeaker One

        2.0\t4.0\tSpeaker Two
        """
        let intervals = try RTTMParser.parseTSV(tsv)
        #expect(intervals.count == 2)
        #expect(intervals[0].speaker == "Speaker One")
        #expect(intervals[1].speaker == "Speaker Two")
    }

    @Test("列不足の TSV 行は malformedLine を投げる")
    func tsvMalformed() {
        let tsv = "0.0\tspk_A"
        #expect(throws: RTTMParser.ParseError.self) {
            _ = try RTTMParser.parseTSV(tsv)
        }
    }
}
