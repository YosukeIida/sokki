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
}
