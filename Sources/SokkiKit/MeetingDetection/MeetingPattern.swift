import Foundation

/// マッチした際の確信度。数値が大きいほど確信度が高い（複数マッチ時は最大値を採用）。
enum MeetingConfidence: Int, Comparable, Sendable {
    case low = 1
    case medium = 2
    case high = 3

    static func < (lhs: MeetingConfidence, rhs: MeetingConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// ウィンドウタイトルに対する部分一致パターン。正規表現は使わず `String.contains` のみで判定する。
struct MeetingPattern: Sendable {
    let keyword: String
    let confidence: MeetingConfidence
    let caseSensitive: Bool
    let excludePatterns: [String]

    init(
        keyword: String,
        confidence: MeetingConfidence,
        caseSensitive: Bool = false,
        excludePatterns: [String] = []
    ) {
        self.keyword = keyword
        self.confidence = confidence
        self.caseSensitive = caseSensitive
        self.excludePatterns = excludePatterns
    }

    /// 指定タイトルに一致するか（excludePatterns に一致した場合は false）。
    ///
    /// keyword の一致は単語境界（前後が英数字でないこと）を要求する。単純な部分一致だと
    /// 例えば汎用キーワード "call" が "Recall" に、"sync" が "Async" に意図せずマッチしてしまう
    /// （`String.contains` のみを使うという設計判断は維持しつつ、境界チェックのみ追加する）。
    func matches(title: String) -> Bool {
        let normalizedTitle = caseSensitive ? title : title.lowercased()
        let normalizedKeyword = caseSensitive ? keyword : keyword.lowercased()

        guard Self.containsWholeWord(normalizedTitle, keyword: normalizedKeyword) else { return false }

        // excludePatterns は keyword の caseSensitive 設定に関係なく常に大小文字を無視して判定する
        // （タイトルの表記ゆれ「Chat」「chat」等に頑健にするため）。
        let lowercasedTitle = title.lowercased()
        for exclude in excludePatterns where lowercasedTitle.contains(exclude.lowercased()) {
            return false
        }
        return true
    }

    /// `haystack` 内に `keyword` が単語境界つきで出現するか（正規表現は使わない）。
    /// 一致直前・直後の文字が英数字でなければ境界とみなす（文字列の先頭・末尾も境界）。
    /// 最初の出現が境界条件を満たさなくても、以降の出現を走査して境界を満たすものを探す
    /// （例: "call this a recall or a call" は "recall" 部分ではなく後方の独立した "call" で一致する）。
    private static func containsWholeWord(_ haystack: String, keyword: String) -> Bool {
        guard !keyword.isEmpty else { return false }
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: keyword, range: searchRange) {
            let beforeOK: Bool
            if found.lowerBound == haystack.startIndex {
                beforeOK = true
            } else {
                let before = haystack[haystack.index(before: found.lowerBound)]
                beforeOK = !(before.isLetter || before.isNumber)
            }
            let afterOK: Bool
            if found.upperBound == haystack.endIndex {
                afterOK = true
            } else {
                let after = haystack[found.upperBound]
                afterOK = !(after.isLetter || after.isNumber)
            }
            if beforeOK && afterOK { return true }
            searchRange = found.upperBound..<haystack.endIndex
        }
        return false
    }
}

/// 汎用的な会議キーワード（アプリ固有パターンに追加で適用する）。
/// bundleID フィルタ後のウィンドウにのみ適用するため、対象アプリのウィンドウでのみ誤検知リスクを負う。
let commonMeetingPatterns: [MeetingPattern] = [
    MeetingPattern(keyword: "meeting", confidence: .low),
    MeetingPattern(keyword: "call", confidence: .low),
    MeetingPattern(keyword: "sync", confidence: .low),
    MeetingPattern(keyword: "daily", confidence: .low),
    MeetingPattern(keyword: "retro", confidence: .low),
    MeetingPattern(keyword: "refinement", confidence: .low),
]
