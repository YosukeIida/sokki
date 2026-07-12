import Testing
@testable import SokkiKit

@Suite("ConfirmedBoundaryTracker")
struct ConfirmedBoundaryTrackerTests {

    private func seg(_ text: String, _ start: Float, _ end: Float) -> DecodedSegment {
        DecodedSegment(start: start, end: end, text: text)
    }

    @Test("required 本以下は全て hypothesis になり確定はゼロ")
    func fewerThanRequiredStayHypothesis() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 2)
        let update = tracker.ingest([seg("あ", 0, 1), seg("い", 1, 2)])

        #expect(update.newlyConfirmed.isEmpty)
        #expect(update.hypothesis == "あい")
        #expect(tracker.lastConfirmedEnd == 0)
    }

    @Test("確定境界: 末尾 required 本を残して前を確定する")
    func confirmsPrefixKeepingRequiredTail() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 2)
        let update = tracker.ingest([
            seg("A", 0, 1),
            seg("B", 1, 2),
            seg("C", 2, 3),
            seg("D", 3, 4),
        ])

        // 4 - 2 = 2 本（A, B）が確定、末尾 2 本（C, D）が hypothesis。
        #expect(update.newlyConfirmed.map(\.text) == ["A", "B"])
        #expect(update.hypothesis == "CD")
        #expect(tracker.lastConfirmedEnd == 2)
    }

    @Test("hypothesis→confirmed の遷移: 再デコードで前回の未確定が確定に移る")
    func hypothesisBecomesConfirmedOnNextDecode() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 2)

        // 1回目: A 確定、B・C は hypothesis
        let first = tracker.ingest([seg("A", 0, 1), seg("B", 1, 2), seg("C", 2, 3)])
        #expect(first.newlyConfirmed.map(\.text) == ["A"])
        #expect(first.hypothesis == "BC")
        #expect(tracker.lastConfirmedEnd == 1)

        // 2回目: clip 起点 1 秒から再デコードされた列（B, C, D）。B が確定に移り、C・D が hypothesis。
        let second = tracker.ingest([seg("B", 1, 2), seg("C", 2, 3), seg("D", 3, 4)])
        #expect(second.newlyConfirmed.map(\.text) == ["B"])
        #expect(second.hypothesis == "CD")
        #expect(tracker.lastConfirmedEnd == 2)
    }

    @Test("境界が前進しない場合は確定しない")
    func noConfirmWhenBoundaryDoesNotAdvance() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 1)

        _ = tracker.ingest([seg("A", 0, 5), seg("B", 5, 6)]) // A 確定, end=5
        #expect(tracker.lastConfirmedEnd == 5)

        // prefix の末尾 end(4) <= lastConfirmedEnd(5) → 確定しない
        let update = tracker.ingest([seg("X", 3, 4), seg("Y", 6, 7)])
        #expect(update.newlyConfirmed.isEmpty)
        #expect(tracker.lastConfirmedEnd == 5)
        #expect(update.hypothesis == "Y")
    }

    @Test("停止時 flush: 残り hypothesis を全て確定し hypothesis を空にする")
    func flushConfirmsRemainingAndClearsHypothesis() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 2)

        let live = tracker.ingest([seg("A", 0, 1), seg("B", 1, 2), seg("C", 2, 3)])
        #expect(live.newlyConfirmed.map(\.text) == ["A"])
        #expect(live.hypothesis == "BC")

        // flush: 確定境界(1秒)より後ろの B・C を確定
        let flushed = tracker.flush([seg("A", 0, 1), seg("B", 1, 2), seg("C", 2, 3)])
        #expect(flushed.newlyConfirmed.map(\.text) == ["B", "C"])
        #expect(flushed.hypothesis == "")
        #expect(tracker.lastConfirmedEnd == 3)
    }

    @Test("空・空白テキストのセグメントは確定・hypothesis から除外される")
    func blankSegmentsAreDropped() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 1)
        // 3 本 → 2 本確定（A, 空白）。空白は snapshot から除外され A のみ残る。
        let update = tracker.ingest([seg("A", 0, 1), seg("   ", 1, 2), seg("C", 2, 3)])
        #expect(update.newlyConfirmed.map(\.text) == ["A"])
        // hypothesis は末尾 1 本（C）
        #expect(update.hypothesis == "C")
    }

    @Test("確定セグメントのテキストは前後空白がトリムされる")
    func confirmedTextIsTrimmed() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 1)
        let update = tracker.ingest([seg(" hello", 0, 1), seg(" world", 1, 2)])
        #expect(update.newlyConfirmed.map(\.text) == ["hello"])
        // hypothesis は連結後にトリム
        #expect(update.hypothesis == "world")
    }
}
