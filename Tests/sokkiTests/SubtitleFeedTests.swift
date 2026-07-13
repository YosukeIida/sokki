import Testing
import Foundation
@testable import SokkiKit

@Suite("SubtitleFeed 組み立て・トリム")
@MainActor
struct SubtitleFeedTests {

    private func output(_ id: UUID, _ text: String, _ time: TimeInterval) -> TranslationOutput {
        TranslationOutput(id: id, translatedText: text, isConcluded: true, sourceTime: time)
    }

    @Test("原文 push のみ → 訳文未到着は translated == nil、sourceTime 昇順")
    func originalsOnly() {
        let feed = SubtitleFeed(maxLines: 6)
        let ids = (0..<3).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            feed.pushConfirmed(id: id, text: "orig\(i)", sourceTime: TimeInterval(i))
        }

        let lines = feed.makeLines(translations: [:])
        #expect(lines.map(\.original) == ["orig0", "orig1", "orig2"])
        #expect(lines.allSatisfy { $0.translated == nil })
        #expect(lines.map(\.id) == ids)
    }

    @Test("訳文が順不同・遅延到着でも id で正しく対応付く")
    func outOfOrderTranslations() {
        let feed = SubtitleFeed(maxLines: 6)
        let ids = (0..<4).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            feed.pushConfirmed(id: id, text: "orig\(i)", sourceTime: TimeInterval(i))
        }

        // 訳文辞書を意図的に逆順・部分的に構築（順不同・一部未到着）。
        var translations: [UUID: TranslationOutput] = [:]
        translations[ids[3]] = output(ids[3], "trans3", 3)
        translations[ids[0]] = output(ids[0], "trans0", 0)
        translations[ids[2]] = output(ids[2], "trans2", 2)
        // ids[1] は未到着。

        let lines = feed.makeLines(translations: translations)
        #expect(lines.count == 4)
        #expect(lines[0].translated == "trans0")
        #expect(lines[1].translated == nil)      // 未到着
        #expect(lines[2].translated == "trans2")
        #expect(lines[3].translated == "trans3")
        // 原文の並びは崩れない。
        #expect(lines.map(\.original) == ["orig0", "orig1", "orig2", "orig3"])
    }

    @Test("maxLines を超えたら最新 N 行にトリムされ、古い行は落ちる")
    func trimToMaxLines() {
        let feed = SubtitleFeed(maxLines: 3)
        var ids: [UUID] = []
        for i in 0..<6 {
            let id = UUID()
            ids.append(id)
            feed.pushConfirmed(id: id, text: "orig\(i)", sourceTime: TimeInterval(i))
        }

        let lines = feed.makeLines(translations: [:])
        #expect(lines.count == 3)
        #expect(lines.map(\.original) == ["orig3", "orig4", "orig5"])   // 最新 3 行。

        // 落ちた古い行の id に訳文が来ても復活しない。
        let stale = output(ids[0], "stale", 0)
        let lines2 = feed.makeLines(translations: [ids[0]: stale])
        #expect(lines2.contains { $0.id == ids[0] } == false)
    }

    @Test("同一 id の再 push はテキストを更新し、挿入順・行数は変えない")
    func rePushUpdatesInPlace() {
        let feed = SubtitleFeed(maxLines: 4)
        let a = UUID(); let b = UUID()
        feed.pushConfirmed(id: a, text: "a1", sourceTime: 0)
        feed.pushConfirmed(id: b, text: "b1", sourceTime: 1)
        feed.pushConfirmed(id: a, text: "a2", sourceTime: 0)   // 訂正。

        let lines = feed.makeLines(translations: [:])
        #expect(lines.count == 2)
        #expect(lines.map(\.original) == ["a2", "b1"])
    }

    @Test("同一 sourceTime は到着順で安定ソートされる")
    func stableSortForEqualSourceTime() {
        let feed = SubtitleFeed(maxLines: 6)
        let first = UUID(); let second = UUID(); let third = UUID()
        feed.pushConfirmed(id: first, text: "first", sourceTime: 5)
        feed.pushConfirmed(id: second, text: "second", sourceTime: 5)
        feed.pushConfirmed(id: third, text: "third", sourceTime: 5)

        let lines = feed.makeLines(translations: [:])
        #expect(lines.map(\.original) == ["first", "second", "third"])
    }

    @Test("reset で全行クリア")
    func resetClears() {
        let feed = SubtitleFeed(maxLines: 6)
        feed.pushConfirmed(id: UUID(), text: "x", sourceTime: 0)
        feed.reset()
        #expect(feed.makeLines(translations: [:]).isEmpty)
    }

    @Test("maxLines は最小 1 に丸められる")
    func maxLinesClamped() {
        let feed = SubtitleFeed(maxLines: 0)
        feed.pushConfirmed(id: UUID(), text: "a", sourceTime: 0)
        feed.pushConfirmed(id: UUID(), text: "b", sourceTime: 1)
        let lines = feed.makeLines(translations: [:])
        #expect(lines.count == 1)
        #expect(lines.first?.original == "b")
    }

    @Test("init 後に maxLines を 0/負値へ変更しても 1 に丸められ、クラッシュしない")
    func maxLinesSetterClampsAfterInit() {
        let feed = SubtitleFeed(maxLines: 6)
        feed.pushConfirmed(id: UUID(), text: "a", sourceTime: 0)
        feed.pushConfirmed(id: UUID(), text: "b", sourceTime: 1)

        feed.maxLines = -3
        #expect(feed.maxLines == 1)
        // 丸め後、即座に再トリムされる（次の pushConfirmed を待たない）。
        let lines = feed.makeLines(translations: [:])
        #expect(lines.count == 1)
        #expect(lines.first?.original == "b")
    }

    @Test("負値クランプ後に内部ストレージも即座にトリムされる（表示 suffix だけに頼らない）")
    func maxLinesSetterTrimsInternalStorageNotJustDisplay() {
        // `makeLines` は常に `suffix(maxLines)` で表示件数を絞るため、内部の
        // `order`/`originals` が実際にトリムされていなくても、直後の `makeLines` 呼び出し
        // だけでは検出できない。maxLines を丸めた後にもう一度大きく増やし、
        // 内部ストレージから本当に落ちているか（増やしても復活しないか）を確認する。
        let feed = SubtitleFeed(maxLines: 6)
        let ids = (0..<5).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            feed.pushConfirmed(id: id, text: "orig\(i)", sourceTime: TimeInterval(i))
        }
        #expect(feed.makeLines(translations: [:]).count == 5)

        feed.maxLines = -1   // 1 に丸められ、didSet 内で trim() が明示的に呼ばれるべき。
        #expect(feed.maxLines == 1)

        feed.maxLines = 10   // 増やしても、内部ストレージから既に落ちた行は復活しない。
        let lines = feed.makeLines(translations: [:])
        #expect(lines.count == 1)
        #expect(lines.first?.original == "orig4")
    }

    @Test("原文が sourceTime の昇順以外で到着しても trim は表示と同じ基準（sourceTime）で古い行を落とす")
    func trimUsesSourceTimeOrderNotInsertionOrder() {
        let feed = SubtitleFeed(maxLines: 3)
        let idOld = UUID()   // 挿入は最初だが sourceTime は最も新しい。
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()

        feed.pushConfirmed(id: idOld, text: "old-but-inserted-first", sourceTime: 100)
        feed.pushConfirmed(id: idA, text: "a", sourceTime: 1)
        feed.pushConfirmed(id: idB, text: "b", sourceTime: 2)
        feed.pushConfirmed(id: idC, text: "c", sourceTime: 3)   // ここで4件目 → 1件トリム。

        let lines = feed.makeLines(translations: [:])
        // sourceTime で見て最新3件（2, 3, 100）が残るべき。挿入順トリムだと挿入順最古の
        // idOld（sourceTime=100 で本来は最新）が誤って落とされ、代わりに sourceTime=1
        // （本来最も古く落とすべき idA）が残ってしまう。
        #expect(lines.map(\.original) == ["b", "c", "old-but-inserted-first"])
        #expect(lines.count == 3)
    }
}
