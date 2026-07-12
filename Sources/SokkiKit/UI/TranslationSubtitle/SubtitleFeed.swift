import Foundation

/// 2レーン字幕の1行分の表示値（原文 + 任意の訳文）。
///
/// `id` は原文セグメント（= `TranslationInput.id` = clientID）と同一キー。訳文は
/// `TranslationCoordinator.translations[id]` から遅延・順不同で到着しうるため、
/// 表示側は必ず `id` で突き合わせる（`sourceTime` は安定ソート用の補助）。
public struct SubtitleLine: Identifiable, Equatable, Sendable {
    /// = clientID。原文セグメント / `TranslationInput` と同一キー。
    public let id: UUID
    public let original: String
    /// 訳文（未到着なら `nil`）。
    public var translated: String?
    /// セグメント開始時刻（並び順・行対応の補助）。
    public let sourceTime: TimeInterval

    public init(id: UUID, original: String, translated: String?, sourceTime: TimeInterval) {
        self.id = id
        self.original = original
        self.translated = translated
        self.sourceTime = sourceTime
    }
}

/// 2レーン字幕の表示モデル。確定原文列と `TranslationCoordinator` の訳文辞書を
/// `id` で突き合わせ、最新 N 行に絞った表示行 (`SubtitleLine`) を組み立てる。
///
/// **文字起こし側との結線点は `pushConfirmed(id:text:sourceTime:)` の1つに絞る。**
/// 上流マージ後、`TranscriptionPipeline` の確定セグメント分岐（partial は渡さない）から
/// このメソッドを呼ぶ。訳文は本モデルに push せず、描画時に
/// `makeLines(translations:)` へ `coordinator.translations` を渡して合流させる
/// （訳文の遅延・順序逆転に強い設計。`docs/translation-architecture.md` §10）。
///
/// `@Observable` なので `makeLines` を SwiftUI ビュー body 内で呼べば、原文列の変化で
/// 再描画される。訳文側は呼び出し元が `coordinator.translations` を読むことで追跡される。
@MainActor
@Observable
public final class SubtitleFeed {
    /// 表示・保持する最新行数。これを超えた古い確定原文はトリムする（メモリ抑制）。
    public var maxLines: Int

    private struct OriginalLine {
        let text: String
        let sourceTime: TimeInterval
    }

    /// 確定原文の到着順（挿入順）。同一 `sourceTime` の安定ソートのタイブレークに使う。
    private var order: [UUID] = []
    private var originals: [UUID: OriginalLine] = [:]

    public init(maxLines: Int = 6) {
        self.maxLines = max(1, maxLines)
    }

    /// 唯一の文字起こし側結線点。確定セグメントの原文を push する。
    ///
    /// - partial は渡さない（`TranslationCoordinator.submitConfirmed` と同じ「確定のみ」契約）。
    /// - 同一 `id` の再 push はテキストを更新する（確定訂正に備える）。挿入順は初出時のみ記録。
    public func pushConfirmed(id: UUID, text: String, sourceTime: TimeInterval) {
        if originals[id] == nil {
            order.append(id)
        }
        originals[id] = OriginalLine(text: text, sourceTime: sourceTime)
        trim()
    }

    /// 全行クリア（録音開始・停止など、セッション境界で呼ぶ）。
    public func reset() {
        order.removeAll()
        originals.removeAll()
    }

    /// 訳文辞書と結合して表示行を組み立てる。
    ///
    /// 保持中の確定原文を `sourceTime` 昇順（同時刻は到着順で安定化）に並べ、最新 `maxLines`
    /// 行へ絞ったうえで、各行に `translations[id]` の訳文を合流させる。訳文は順不同・遅延到着で
    /// よく、未到着行は `translated == nil`（表示側で「翻訳待ち」を出せる）。
    ///
    /// - Parameter translations: `TranslationCoordinator.translations` 相当（`id` キー）。
    public func makeLines(translations: [UUID: TranslationOutput]) -> [SubtitleLine] {
        let present: [(index: Int, id: UUID, line: OriginalLine)] =
            order.enumerated().compactMap { index, id in
                guard let line = originals[id] else { return nil }
                return (index, id, line)
            }

        let sorted = present.sorted { lhs, rhs in
            if lhs.line.sourceTime != rhs.line.sourceTime {
                return lhs.line.sourceTime < rhs.line.sourceTime
            }
            return lhs.index < rhs.index   // 同時刻は到着順で安定化。
        }

        return sorted.suffix(maxLines).map { _, id, line in
            SubtitleLine(
                id: id,
                original: line.text,
                translated: translations[id]?.translatedText,
                sourceTime: line.sourceTime
            )
        }
    }

    /// 保持する原文を最新 `maxLines` 件に抑える。
    ///
    /// 確定セグメントは通常 `sourceTime` 昇順（= 挿入順）で到着するため、挿入順で古いものから
    /// 落とす。順序が乱れうる将来のために、落とすのは表示に載らない最古行に限る。
    private func trim() {
        guard order.count > maxLines else { return }
        let dropCount = order.count - maxLines
        for id in order.prefix(dropCount) {
            originals[id] = nil
        }
        order.removeFirst(dropCount)
    }
}
