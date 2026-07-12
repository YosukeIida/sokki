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
