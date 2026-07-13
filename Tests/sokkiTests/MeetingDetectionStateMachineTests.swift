import Testing
@testable import SokkiKit

@Suite("MeetingDetectionStateMachine")
struct MeetingDetectionStateMachineTests {

    private static let candidateA = MeetingCandidate(app: .zoom, title: "Zoom Meeting", confidence: .high)
    private static let candidateB = MeetingCandidate(app: .teams, title: "Standup | Microsoft Teams", confidence: .high)

    @Test("検出されたら提案を返す")
    func detectedReturnsSuggestion() {
        var sm = MeetingDetectionStateMachine()
        let suggestion = sm.evaluate(detected: Self.candidateA)
        #expect(suggestion == Self.candidateA)
    }

    @Test("拒否後、同一会議（同じkey）が検出され続けても再提案しない")
    func dismissedSuppressesSameSession() {
        var sm = MeetingDetectionStateMachine()
        _ = sm.evaluate(detected: Self.candidateA)
        sm.markDismissed(key: Self.candidateA.key)

        let suggestion = sm.evaluate(detected: Self.candidateA)
        #expect(suggestion == nil)
    }

    @Test("拒否後も別の会議（別のkey）は提案される")
    func dismissedDoesNotSuppressDifferentMeeting() {
        var sm = MeetingDetectionStateMachine()
        sm.markDismissed(key: Self.candidateA.key)

        let suggestion = sm.evaluate(detected: Self.candidateB)
        #expect(suggestion == Self.candidateB)
    }

    @Test("会議が連続して検出されなくなる（セッション終了）と拒否状態がリセットされる")
    func meetingEndedResetsDismissal() {
        var sm = MeetingDetectionStateMachine(missesBeforeReset: 2)
        _ = sm.evaluate(detected: Self.candidateA)
        sm.markDismissed(key: Self.candidateA.key)
        #expect(sm.evaluate(detected: Self.candidateA) == nil)

        // 会議が終了（2回連続で検出されなくなる）
        #expect(sm.evaluate(detected: nil) == nil)
        #expect(sm.evaluate(detected: nil) == nil)

        // 同じタイトルの会議が再開しても新しいセッションとして再提案される
        let suggestion = sm.evaluate(detected: Self.candidateA)
        #expect(suggestion == Self.candidateA)
    }

    @Test("一時的に1回だけ検出漏れしても拒否状態はリセットされない（同一会議中のタイトル変化に耐性を持つ）")
    func transientSingleMissDoesNotResetDismissal() {
        var sm = MeetingDetectionStateMachine(missesBeforeReset: 2)
        _ = sm.evaluate(detected: Self.candidateA)
        sm.markDismissed(key: Self.candidateA.key)

        // 1回だけ検出漏れ（例: Teams で Chat タブに一時的に切り替わりタイトルが変わった等）
        #expect(sm.evaluate(detected: nil) == nil)

        // すぐに同じ会議が検出され直しても、まだ拒否状態のままなので再提案されない
        let suggestion = sm.evaluate(detected: Self.candidateA)
        #expect(suggestion == nil)
    }

    @Test("reset() で拒否状態を明示的にクリアできる")
    func resetClearsDismissal() {
        var sm = MeetingDetectionStateMachine()
        sm.markDismissed(key: Self.candidateA.key)
        sm.reset()

        let suggestion = sm.evaluate(detected: Self.candidateA)
        #expect(suggestion == Self.candidateA)
    }
}
