import Testing
@testable import SokkiKit

@Suite("MeetingMatcher")
struct MeetingMatcherTests {

    // MARK: - Zoom

    @Test("Zoom: bundleID一致 + 「zoom meeting」タイトルは高確信度でマッチする")
    func zoomMeetingHighConfidence() {
        let window = MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Zoom Meeting")
        let result = MeetingMatcher.match(app: .zoom, window: window)
        #expect(result?.app == .zoom)
        #expect(result?.confidence == .high)
    }

    @Test("Zoom: bundleID一致 + 汎用キーワード（sync）は低確信度でマッチする")
    func zoomCommonPatternLowConfidence() {
        let window = MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Weekly Sync")
        let result = MeetingMatcher.match(app: .zoom, window: window)
        #expect(result?.confidence == .low)
    }

    @Test("Zoom: bundleIDが一致しない場合はタイトルが一致してもマッチしない")
    func nonZoomBundleDoesNotMatch() {
        let window = MeetingWindowInfo(bundleIdentifier: "com.example.other", title: "Zoom Meeting")
        let result = MeetingMatcher.match(app: .zoom, window: window)
        #expect(result == nil)
    }

    // MARK: - Teams

    @Test("Teams: 「| Microsoft Teams」タイトルは高確信度でマッチする")
    func teamsTitleHighConfidence() {
        let window = MeetingWindowInfo(bundleIdentifier: "com.microsoft.teams2", title: "Weekly Standup | Microsoft Teams")
        let result = MeetingMatcher.match(app: .teams, window: window)
        #expect(result?.confidence == .high)
    }

    @Test("Teams: excludePatterns（chat）に一致する場合はマッチしない")
    func teamsChatExcluded() {
        let window = MeetingWindowInfo(bundleIdentifier: "com.microsoft.teams2", title: "Chat | Microsoft Teams")
        let result = MeetingMatcher.match(app: .teams, window: window)
        #expect(result == nil)
    }

    @Test("Teams: excludePatterns（activity）に一致する場合はマッチしない")
    func teamsActivityExcluded() {
        let window = MeetingWindowInfo(bundleIdentifier: "com.microsoft.teams2", title: "Activity | Microsoft Teams")
        let result = MeetingMatcher.match(app: .teams, window: window)
        #expect(result == nil)
    }

    @Test("Teams: 旧bundleID（com.microsoft.teams）でもマッチする")
    func teamsLegacyBundleID() {
        let window = MeetingWindowInfo(bundleIdentifier: "com.microsoft.teams", title: "Call with 田中さん")
        let result = MeetingMatcher.match(app: .teams, window: window)
        #expect(result?.confidence == .high)
    }

    @Test("Teams: 「Daily Chat | Microsoft Teams」は汎用語(daily)経由でもマッチしない（chat除外のすり抜け防止）")
    func teamsChatExcludedEvenViaCommonKeywordFallback() {
        // "| Microsoft Teams" パターンは excludePatterns(chat) で弾かれるが、
        // その後に評価される commonMeetingPatterns の "daily" が低確信度ですり抜けてしまわないことを確認する。
        let window = MeetingWindowInfo(bundleIdentifier: "com.microsoft.teams2", title: "Daily Chat | Microsoft Teams")
        let result = MeetingMatcher.match(app: .teams, window: window)
        #expect(result == nil)
    }

    @Test("Zoom: 汎用語「call」は「Recall」のような単語の一部にはマッチしない（単語境界）")
    func zoomCommonKeywordDoesNotMatchSubstringOfUnrelatedWord() {
        // "| Microsoft Teams" のような別パターンとの混同を避けるため Zoom で検証する。
        let window = MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Recall Notes")
        let result = MeetingMatcher.match(app: .zoom, window: window)
        #expect(result == nil)
    }

    @Test("Zoom: 汎用語「sync」は「Async」のような単語の一部にはマッチしない（単語境界）")
    func zoomCommonKeywordDoesNotMatchAsyncSubstring() {
        let window = MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Async Standup Notes")
        let result = MeetingMatcher.match(app: .zoom, window: window)
        #expect(result == nil)
    }

    @Test("Zoom: 汎用語「call」は単語境界を満たす独立した出現には引き続きマッチする")
    func zoomCommonKeywordStillMatchesWholeWordOccurrence() {
        let window = MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Recall or just call - notes")
        let result = MeetingMatcher.match(app: .zoom, window: window)
        #expect(result?.confidence == .low)
    }

    // MARK: - Google Meet

    @Test("Google Meet: Chromeのタブタイトルに「meet.google.com」があれば高確信度でマッチする")
    func googleMeetURLHighConfidence() {
        let window = MeetingWindowInfo(bundleIdentifier: "com.google.Chrome", title: "meet.google.com/abc-defg-hij")
        let result = MeetingMatcher.match(app: .googleMeet, window: window)
        #expect(result?.confidence == .high)
    }

    @Test("Google Meet: 汎用キーワード（meeting）だけではマッチしない（誤検知対策）")
    func googleMeetCommonPatternExcluded() {
        let window = MeetingWindowInfo(bundleIdentifier: "com.google.Chrome", title: "Random Meeting Notes - Google Docs")
        let result = MeetingMatcher.match(app: .googleMeet, window: window)
        #expect(result == nil)
    }

    @Test("Google Meet: ブラウザ以外のbundleIDはマッチしない")
    func googleMeetNonBrowserBundleDoesNotMatch() {
        let window = MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "meet.google.com/abc-defg-hij")
        let result = MeetingMatcher.match(app: .googleMeet, window: window)
        #expect(result == nil)
    }

    // MARK: - 非該当

    @Test("会議と無関係なウィンドウはどのアプリともマッチしない")
    func unrelatedWindowDoesNotMatch() {
        let window = MeetingWindowInfo(bundleIdentifier: "com.example.notes", title: "買い物リスト")
        for app in MeetingApp.allCases {
            #expect(MeetingMatcher.match(app: app, window: window) == nil)
        }
    }

    @Test("bundleIdentifierがnilの場合はマッチしない")
    func nilBundleIdentifierDoesNotMatch() {
        let window = MeetingWindowInfo(bundleIdentifier: nil, title: "Zoom Meeting")
        #expect(MeetingMatcher.match(app: .zoom, window: window) == nil)
    }

    @Test("titleがnilの場合はマッチしない")
    func nilTitleDoesNotMatch() {
        let window = MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: nil)
        #expect(MeetingMatcher.match(app: .zoom, window: window) == nil)
    }

    // MARK: - bestCandidate

    @Test("bestCandidate は複数ウィンドウの中から最高確信度の候補を返す")
    func bestCandidatePicksHighestConfidence() {
        let windows = [
            MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Weekly Sync"),        // low
            MeetingWindowInfo(bundleIdentifier: "com.microsoft.teams2", title: "Standup | Microsoft Teams"), // high
            MeetingWindowInfo(bundleIdentifier: "com.example.notes", title: "買い物リスト"),  // no match
        ]
        let best = MeetingMatcher.bestCandidate(in: windows)
        #expect(best?.app == .teams)
        #expect(best?.confidence == .high)
    }

    @Test("bestCandidate は該当ウィンドウが無ければnilを返す")
    func bestCandidateReturnsNilWhenNoMatch() {
        let windows = [
            MeetingWindowInfo(bundleIdentifier: "com.example.notes", title: "買い物リスト"),
        ]
        #expect(MeetingMatcher.bestCandidate(in: windows) == nil)
    }
}
