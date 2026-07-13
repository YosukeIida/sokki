import Foundation

/// SCShareableContent をポーリングして会議中のウィンドウを検出し、録音開始の提案を UI に通知する。
///
/// 重要: `start()` が呼ばれるまで `ShareableContentProviding`（＝ SCShareableContent）は一切呼び出さない。
/// 画面収録権限のプロンプトを誘発しうるため、設定で機能が OFF の間はポーリングを開始してはいけない
/// （呼び出し側は `AppSettingsModel.meetingDetectionEnabled` を見て `start()`/`stop()` を切り替える）。
@Observable
@MainActor
final class MeetingDetector {
    /// 提案中の会議候補。ユーザーへのバナー表示に使う。拒否済み・録音中などは nil。
    private(set) var suggestion: MeetingCandidate?

    private let provider: any ShareableContentProviding
    private let pollInterval: Duration
    private var pollingTask: Task<Void, Never>?
    private var stateMachine = MeetingDetectionStateMachine()

    init(
        provider: any ShareableContentProviding = SCShareableContentProvider(),
        pollInterval: Duration = .seconds(15)
    ) {
        self.provider = provider
        self.pollInterval = pollInterval
    }

    /// ポーリングを開始する（既に開始済みなら何もしない）。
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    /// ポーリングを停止し、提案・拒否状態をリセットする。
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        suggestion = nil
        stateMachine.reset()
    }

    /// ユーザーが提案を拒否した。同一会議セッション中は再提案しない。
    func dismissCurrentSuggestion() {
        guard let key = suggestion?.key else { return }
        stateMachine.markDismissed(key: key)
        suggestion = nil
    }

    /// ユーザーが提案を承諾して録音を開始する直前に呼ぶ。バナーを即座に片付ける。
    func acceptCurrentSuggestion() {
        suggestion = nil
    }

    private func poll() async {
        do {
            let windows = try await provider.currentWindows()
            // `provider.currentWindows()` はアクター境界を跨ぐ（実装は SCShareableContent
            // への非同期呼び出し）ため、await 中に `stop()` が呼ばれて `pollingTask` が
            // キャンセルされている可能性がある。ScreenCaptureKit 側の呼び出しは協調的
            // キャンセルに反応するとは限らないため、resume 後に自分で確認しないと
            // stop() 済みの状態を stale な検出結果で上書きしてしまう。
            guard !Task.isCancelled else { return }
            let candidate = MeetingMatcher.bestCandidate(in: windows)
            suggestion = stateMachine.evaluate(detected: candidate)
        } catch {
            guard !Task.isCancelled else { return }
            // 画面収録権限が無い場合など。クラッシュさせずバナーを消すだけに留める。
            suggestion = nil
        }
    }
}
