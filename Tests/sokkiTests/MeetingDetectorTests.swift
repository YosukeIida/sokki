import Testing
@testable import SokkiKit

@Suite("MeetingDetector")
@MainActor
struct MeetingDetectorTests {

    @Test("検出されたウィンドウがあればsuggestionが立つ")
    func startDetectsSuggestion() async throws {
        let provider = MockShareableContentProvider()
        await provider.setStubbedWindows([
            MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Zoom Meeting"),
        ])
        let detector = MeetingDetector(provider: provider, pollInterval: .seconds(60))
        detector.start()

        try await waitUntil { detector.suggestion != nil }

        #expect(detector.suggestion?.app == .zoom)
        #expect(await provider.callCount >= 1)
        detector.stop()
    }

    @Test("拒否するとsuggestionがクリアされ、同一会議は再提案されない")
    func dismissSuppressesSuggestion() async throws {
        let provider = MockShareableContentProvider()
        await provider.setStubbedWindows([
            MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Zoom Meeting"),
        ])
        let detector = MeetingDetector(provider: provider, pollInterval: .milliseconds(20))
        detector.start()
        try await waitUntil { detector.suggestion != nil }

        detector.dismissCurrentSuggestion()
        #expect(detector.suggestion == nil)

        // 拒否後、同じ会議が検出され続けても再提案されない
        try await Task.sleep(for: .milliseconds(100))
        #expect(detector.suggestion == nil)
        detector.stop()
    }

    @Test("stop()を呼ぶとポーリングが止まりsuggestionがクリアされる")
    func stopClearsSuggestion() async throws {
        let provider = MockShareableContentProvider()
        await provider.setStubbedWindows([
            MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Zoom Meeting"),
        ])
        let detector = MeetingDetector(provider: provider, pollInterval: .seconds(60))
        detector.start()
        try await waitUntil { detector.suggestion != nil }

        detector.stop()
        #expect(detector.suggestion == nil)
    }

    @Test("providerがthrowしてもクラッシュせずsuggestionはnilのまま")
    func providerErrorIsSwallowed() async throws {
        let provider = MockShareableContentProvider()
        await provider.setShouldThrow(true)
        let detector = MeetingDetector(provider: provider, pollInterval: .seconds(60))
        detector.start()

        try await Task.sleep(for: .milliseconds(50))
        #expect(detector.suggestion == nil)
        detector.stop()
    }

    @Test("stop()中にin-flightだったpollが後から完了しても、stale な検出結果でsuggestionを復活させない")
    func inFlightPollDoesNotResurrectSuggestionAfterStop() async throws {
        let provider = GatedShareableContentProvider()
        await provider.setStubbedWindows([
            MeetingWindowInfo(bundleIdentifier: "us.zoom.xos", title: "Zoom Meeting"),
        ])
        let detector = MeetingDetector(provider: provider, pollInterval: .seconds(60))
        detector.start()

        // 最初の poll が provider.currentWindows() 内でブロックされるまで少し待つ。
        try await Task.sleep(for: .milliseconds(50))
        #expect(detector.suggestion == nil)

        // in-flight の poll が完了する前に stop() する。
        detector.stop()
        #expect(detector.suggestion == nil)

        // stop() 後に in-flight だった poll を解放し、その結果が反映される猶予を与える。
        await provider.release()
        try await Task.sleep(for: .milliseconds(100))

        // stop() 済みなので、後から届いた検出結果で suggestion が復活してはいけない。
        #expect(detector.suggestion == nil)
    }

    /// 条件が満たされるまで短い間隔でポーリングする（タイムアウト付き）。
    private func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline {
                Issue.record("条件がタイムアウトまでに満たされませんでした")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
