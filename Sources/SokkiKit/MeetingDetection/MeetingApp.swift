import Foundation

/// 検出対象の会議アプリ。`bundleIdentifiers` でウィンドウを絞り込んだ後、`patterns` でタイトルを照合する。
///
/// 参照: `docs/recap-codebase-analysis.md` 会議検出章（Recap の `MeetingDetectorType` 実装群）。
enum MeetingApp: String, CaseIterable, Sendable {
    case zoom
    case teams
    case googleMeet

    var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Microsoft Teams"
        case .googleMeet: return "Google Meet"
        }
    }

    /// このアプリの候補ウィンドウを絞り込むための bundle identifier 集合。
    /// Google Meet はネイティブアプリではなくブラウザのタブなので、対応ブラウザの bundle ID を列挙する。
    var bundleIdentifiers: Set<String> {
        switch self {
        case .zoom:
            return ["us.zoom.xos"]
        case .teams:
            return ["com.microsoft.teams", "com.microsoft.teams2"]
        case .googleMeet:
            return [
                "com.google.Chrome",
                "com.apple.Safari",
                "org.mozilla.firefox",
                "com.microsoft.edgemac",
            ]
        }
    }

    /// このアプリ固有のタイトルパターン。`commonMeetingPatterns` はここには含めない
    /// （`includesCommonPatterns` で適用有無を制御する）。
    var patterns: [MeetingPattern] {
        switch self {
        case .zoom:
            return [
                MeetingPattern(keyword: "zoom meeting", confidence: .high),
                MeetingPattern(keyword: "zoom webinar", confidence: .high),
                MeetingPattern(keyword: "screen share", confidence: .medium),
            ]
        case .teams:
            return [
                MeetingPattern(
                    keyword: "| Microsoft Teams",
                    confidence: .high,
                    caseSensitive: true,
                    excludePatterns: ["chat", "activity"]
                ),
                MeetingPattern(keyword: "call with", confidence: .high),
            ]
        case .googleMeet:
            return [
                MeetingPattern(keyword: "meet.google.com", confidence: .high),
                MeetingPattern(keyword: "google meet", confidence: .high),
            ]
        }
    }

    /// `commonMeetingPatterns`（meeting/call/sync 等の汎用語）を適用するか。
    ///
    /// Google Meet はブラウザの bundle ID（Chrome/Safari/Firefox/Edge）で絞り込むため、
    /// 汎用語を適用すると「会議と無関係などのタブ」まで誤検知してしまう
    /// （Zoom/Teams はアプリ専用ウィンドウのみが対象なのでリスクが小さい）。
    /// このため sokki では Recap の実装から意図的に外し、Google Meet は
    /// `meet.google.com` / `google meet` の高確信度パターンのみで判定する。
    /// 参照: `docs/recap-codebase-analysis.md` 「Google Meet 誤検知リスク」節。
    var includesCommonPatterns: Bool {
        switch self {
        case .zoom, .teams:
            return true
        case .googleMeet:
            return false
        }
    }

    /// `patterns` に `commonMeetingPatterns`（適用対象の場合）を加えた、確信度降順のパターン一覧。
    var allPatterns: [MeetingPattern] {
        let combined = includesCommonPatterns ? patterns + commonMeetingPatterns : patterns
        return combined.sorted { $0.confidence > $1.confidence }
    }
}
