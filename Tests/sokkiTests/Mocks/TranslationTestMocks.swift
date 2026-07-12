import Foundation
import Translation
@testable import SokkiKit

/// 固定の `LanguageAvailability.Status` を返す注入可能な可用性チェッカ。
struct MockAvailability: AvailabilityChecking {
    let stub: LanguageAvailability.Status

    func status(from: Locale.Language, to: Locale.Language) async -> LanguageAvailability.Status {
        stub
    }
}

/// 登録済みキー集合を持つ注入可能な API キーチェッカ。
struct MockAPIKeyChecking: APIKeyChecking {
    let keys: Set<String>

    init(keys: Set<String> = []) { self.keys = keys }

    func hasKey(for providerID: String) -> Bool { keys.contains(providerID) }
}

/// `prepare()` を continuation で任意に停止できる provider。
///
/// 「`prepare()` 実行中に別 `reconcile` が完了する」レース（BLOCKER）の回帰テスト用。
/// `prepare` は `releasePrepare()` が呼ばれるまで suspend し続ける。
actor BlockingTranslationProvider: TranslationProvider {
    nonisolated let providerID: String
    nonisolated let isOnDevice: Bool

    private var prepareContinuation: CheckedContinuation<Void, Error>?
    private(set) var prepareStarted = false
    private(set) var didCompletePrepare = false
    private(set) var teardownCallCount = 0

    init(providerID: String = "blocking", isOnDevice: Bool = false) {
        self.providerID = providerID
        self.isOnDevice = isOnDevice
    }

    func prepare(source: Locale.Language, target: Locale.Language) async throws {
        prepareStarted = true
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            prepareContinuation = c
        }
        didCompletePrepare = true
    }

    /// 停止中の `prepare()` を正常復帰させる。
    func releasePrepare() {
        prepareContinuation?.resume()
        prepareContinuation = nil
    }

    func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func teardown() async {
        teardownCallCount += 1
        // teardown が prepare を停止解除する経路も塞がない（実 provider の冪等クローズに倣う）。
        prepareContinuation?.resume()
        prepareContinuation = nil
    }
}
