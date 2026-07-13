import Foundation

/// `SCShareableContent` の `SCWindow` から必要な情報だけを取り出したテスト可能な値型。
struct MeetingWindowInfo: Sendable, Equatable {
    let bundleIdentifier: String?
    let title: String?

    init(bundleIdentifier: String?, title: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
}

/// 検出された会議候補。
struct MeetingCandidate: Sendable, Equatable {
    let app: MeetingApp
    let title: String
    let confidence: MeetingConfidence

    /// 同一会議セッションを識別するためのキー（アプリ名 + タイトル）。
    /// タイトルが変化すると別セッション扱いになる点は既知の制約（Recap の `MeetingState` と同じ定義）。
    var key: String { "\(app.rawValue)|\(title)" }
}

/// bundleID + タイトルパターンで会議ウィンドウを判定する純粋関数群。
/// SCShareableContent 等の副作用のある API には一切依存しない。
enum MeetingMatcher {

    /// 単一ウィンドウが指定アプリの会議ウィンドウとして判定できるかどうか。
    static func match(app: MeetingApp, window: MeetingWindowInfo) -> MeetingCandidate? {
        guard let bundleIdentifier = window.bundleIdentifier,
              app.bundleIdentifiers.contains(bundleIdentifier) else {
            return nil
        }
        guard let title = window.title, !title.isEmpty else { return nil }

        // アプリ単位の除外語は commonMeetingPatterns 経由のすり抜けを防ぐため、
        // 個別パターンの判定より先に一度だけチェックする。
        let lowercasedTitle = title.lowercased()
        guard !app.commonExcludePatterns.contains(where: { lowercasedTitle.contains($0.lowercased()) }) else {
            return nil
        }

        // allPatterns は確信度降順に並んでいるため、最初に一致したものが最高確信度。
        for pattern in app.allPatterns where pattern.matches(title: title) {
            return MeetingCandidate(app: app, title: title, confidence: pattern.confidence)
        }
        return nil
    }

    /// 全アプリ・全ウィンドウの中から最高確信度の会議候補を1件返す。
    /// 複数のウィンドウが該当する場合は confidence が最大のものを優先する。
    static func bestCandidate(in windows: [MeetingWindowInfo]) -> MeetingCandidate? {
        var best: MeetingCandidate?
        for window in windows {
            for app in MeetingApp.allCases {
                guard let candidate = match(app: app, window: window) else { continue }
                if best == nil || candidate.confidence > best!.confidence {
                    best = candidate
                }
            }
        }
        return best
    }
}
