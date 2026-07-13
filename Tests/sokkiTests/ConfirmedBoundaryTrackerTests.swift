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

    @Test("flush フォールバック: 最終デコードが空でも保持中 hypothesis を確定する")
    func flushFallsBackToPendingWhenFinalDecodeEmpty() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 2)

        // A 確定、B・C は hypothesis として保持
        let live = tracker.ingest([seg("A", 0, 1), seg("B", 1, 2), seg("C", 2, 3)])
        #expect(live.newlyConfirmed.map(\.text) == ["A"])
        #expect(live.hypothesis == "BC")

        // 最終デコードが空配列を返しても、保持中の B・C が確定される（消失しない）
        let flushed = tracker.flush([])
        #expect(flushed.newlyConfirmed.map(\.text) == ["B", "C"])
        #expect(flushed.hypothesis == "")
        #expect(tracker.lastConfirmedEnd == 3)
    }

    @Test("flush フォールバック: 最終デコードが有効ならそちらを優先する")
    func flushPrefersFinalDecodeWhenNonEmpty() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 2)
        _ = tracker.ingest([seg("A", 0, 1), seg("B", 1, 2), seg("C", 2, 3)]) // A 確定, pending=[B,C]

        // 最終デコードが確定境界(1秒)以降を精緻化して返した場合はそちらを確定
        let flushed = tracker.flush([seg("B2", 1, 2), seg("C2", 2, 3), seg("D2", 3, 4)])
        #expect(flushed.newlyConfirmed.map(\.text) == ["B2", "C2", "D2"])
        #expect(flushed.hypothesis == "")
        #expect(tracker.lastConfirmedEnd == 4)
    }

    @Test("flush 部分デコード: 最終結果が pending の一部しか返さなくても末尾を補完する")
    func flushRecoversPendingTailOnPartialDecode() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 2)
        // A 確定、B・C は hypothesis として保持
        _ = tracker.ingest([seg("A", 0, 1), seg("B", 1, 2), seg("C", 2, 3)])

        // 最終デコードが B'（1–2）しか返さない場合でも、pending の末尾 C（2–3）が失われない。
        let flushed = tracker.flush([seg("B2", 1, 2)])
        #expect(flushed.newlyConfirmed.map(\.text) == ["B2", "C"])
        #expect(flushed.hypothesis == "")
        #expect(tracker.lastConfirmedEnd == 3)
    }

    @Test("二重確定の防止: 既確定境界より前の prefix セグメントは再確定しない")
    func doesNotReconfirmSegmentsBeforeBoundary() {
        var tracker = ConfirmedBoundaryTracker(requiredSegments: 1)

        // 境界を 6 秒まで進める
        let first = tracker.ingest([seg("X", 0, 6), seg("Y", 6, 6.2)])
        #expect(first.newlyConfirmed.map(\.text) == ["X"])
        #expect(tracker.lastConfirmedEnd == 6)

        // prefix = [P(end=4.5, 既確定領域), Q(end=7)] → P は除外され Q のみ確定
        let second = tracker.ingest([seg("P", 4, 4.5), seg("Q", 6.5, 7), seg("R", 7, 8)])
        #expect(second.newlyConfirmed.map(\.text) == ["Q"])
        #expect(tracker.lastConfirmedEnd == 7)
        #expect(second.hypothesis == "R")
    }
}
