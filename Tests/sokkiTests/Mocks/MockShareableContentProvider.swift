@testable import SokkiKit

/// `SCShareableContent` をモックする境界。テストでは実際の画面収録権限に依存せずに
/// `MeetingDetector` のポーリングロジックを検証できる。
actor MockShareableContentProvider: ShareableContentProviding {
    var stubbedWindows: [MeetingWindowInfo] = []
    var shouldThrow = false
    private(set) var callCount = 0

    func setStubbedWindows(_ windows: [MeetingWindowInfo]) {
        stubbedWindows = windows
    }

    func setShouldThrow(_ value: Bool) {
        shouldThrow = value
    }

    struct MockError: Error {}

    func currentWindows() async throws -> [MeetingWindowInfo] {
        callCount += 1
        if shouldThrow {
            throw MockError()
        }
        return stubbedWindows
    }
}

/// `currentWindows()` の返却を手動で `release()` するまで保留できるモック。
/// `MeetingDetector.stop()` が呼ばれている最中に in-flight の poll が完了するケース
/// （stop() 後に stale な検出結果で状態を上書きしてしまわないか）を再現するために使う。
actor GatedShareableContentProvider: ShareableContentProviding {
    private var stubbedWindows: [MeetingWindowInfo] = []
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []

    func setStubbedWindows(_ windows: [MeetingWindowInfo]) {
        stubbedWindows = windows
    }

    /// 保留中の呼び出し（あれば）を1件解放する。
    func release() {
        guard !pendingContinuations.isEmpty else { return }
        let continuation = pendingContinuations.removeFirst()
        continuation.resume()
    }

    func currentWindows() async throws -> [MeetingWindowInfo] {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingContinuations.append(continuation)
        }
        return stubbedWindows
    }
}
