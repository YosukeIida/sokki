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
    func matches(title: String) -> Bool {
        let normalizedTitle = caseSensitive ? title : title.lowercased()
        let normalizedKeyword = caseSensitive ? keyword : keyword.lowercased()

        guard normalizedTitle.contains(normalizedKeyword) else { return false }

        // excludePatterns は keyword の caseSensitive 設定に関係なく常に大小文字を無視して判定する
        // （タイトルの表記ゆれ「Chat」「chat」等に頑健にするため）。
        let lowercasedTitle = title.lowercased()
        for exclude in excludePatterns where lowercasedTitle.contains(exclude.lowercased()) {
            return false
        }
        return true
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
