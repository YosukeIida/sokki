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
