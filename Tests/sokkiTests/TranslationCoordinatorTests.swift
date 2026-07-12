import Testing
import Foundation
import Translation
@testable import SokkiKit

@Suite("TranslationCoordinator ライフサイクル")
@MainActor
struct TranslationCoordinatorTests {

    private let ja = Locale.Language(identifier: "ja")
    private let en = Locale.Language(identifier: "en")

    private func ctx(
        preferred: TranslationProviderKind = .auto,
        privacy: Bool,
        keys: Set<TranslationProviderKind> = [],
        order: [TranslationProviderKind] = []
    ) -> RoutingContext {
        RoutingContext(
            enabled: true, preferred: preferred, source: ja, target: en,
            privacyMode: privacy, availableKeys: keys, cloudPreferenceOrder: order
        )
    }

    /// 条件が満たされるまで（または timeout まで）MainActor を明け渡して待つ。
    private func waitUntil(timeout: Duration = .seconds(3), _ cond: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !cond() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // テスト2: privacy ON + auto + Apple 未対応 → クラウド送信ゼロ回帰
    @Test("privacy ON + auto + Apple 未対応 ではクラウド provider の prepare が一度も呼ばれない")
    func cloudNeverPreparedUnderPrivacy() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true)
        let cloud = MockTranslationProvider(providerID: "deepL", isOnDevice: false)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .unsupported)),
            keychain: MockAPIKeyChecking(keys: ["deepL"]),
            appleProvider: apple,
            makeBYO: { _ in cloud }
        )

        await coordinator.reconcile(ctx: ctx(privacy: true, keys: [.deepL], order: [.deepL]))

        #expect(coordinator.hasActiveProvider == false)
        #expect(coordinator.isCloudActive == false)
        let prepared = await cloud.prepareCallCount
        #expect(prepared == 0)   // ← クラウド送信ゼロ
        #expect(coordinator.statusBanner == "プライバシーモードのため自動クラウド翻訳は無効です")
    }

    // テスト4: privacyMode 反転 → reconcile で active==nil かつ Mock teardown
    @Test("privacyMode 反転 → reconcile で active==nil かつ Mock teardown 呼び出し")
    func privacyToggleTearsDown() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true)
        let cloud = MockTranslationProvider(providerID: "deepL", isOnDevice: false)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .unsupported)),
            keychain: MockAPIKeyChecking(keys: ["deepL"]),
            appleProvider: apple,
            makeBYO: { _ in cloud }
        )

        // privacy OFF → クラウド activate
        await coordinator.reconcile(ctx: ctx(privacy: false, keys: [.deepL], order: [.deepL]))
        #expect(coordinator.hasActiveProvider == true)
        #expect(coordinator.isCloudActive == true)
        let preparedBefore = await cloud.prepareCallCount
        #expect(preparedBefore == 1)

        // privacy ON に反転 → reconcile 冒頭の teardown で閉じ、Gate で denied
        await coordinator.reconcile(ctx: ctx(privacy: true, keys: [.deepL], order: [.deepL]))
        #expect(coordinator.hasActiveProvider == false)
        #expect(coordinator.isCloudActive == false)
        let tornDown = await cloud.teardownCallCount
        #expect(tornDown >= 1)
    }

    // テスト5: 出力順シャッフルでも translations[id] が正対応
    @Test("出力順シャッフルでも translations[id] が正しく対応する")
    func idMatchingUnderShuffle() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true, shuffleOutput: true)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .installed)),
            keychain: MockAPIKeyChecking(),
            appleProvider: apple,
            makeBYO: { _ in nil }
        )

        await coordinator.reconcile(ctx: ctx(privacy: true))
        #expect(coordinator.hasActiveProvider == true)

        let inputs = (0..<4).map { i in
            TranslationInput(id: UUID(), text: "seg\(i)", sourceTime: TimeInterval(i))
        }
        for input in inputs { coordinator.submitConfirmed(input) }
        await waitUntil { coordinator.translations.count == inputs.count }

        #expect(coordinator.translations.count == inputs.count)
        for input in inputs {
            #expect(coordinator.translations[input.id]?.id == input.id)
            #expect(coordinator.translations[input.id]?.translatedText == "translated:\(input.text)")
        }
        await coordinator.teardown()
    }

    // テスト6: teardown() で入力 stream finish・pumpTask 終了
    @Test("teardown() で入力ストリームが finish し pumpTask が終了する")
    func teardownStopsPipeline() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .installed)),
            keychain: MockAPIKeyChecking(),
            appleProvider: apple,
            makeBYO: { _ in nil }
        )

        await coordinator.reconcile(ctx: ctx(privacy: false))
        #expect(coordinator.hasActiveProvider == true)

        coordinator.submitConfirmed(TranslationInput(id: UUID(), text: "hello", sourceTime: 0))
        await waitUntil { coordinator.translations.count == 1 }
        #expect(coordinator.translations.count == 1)

        await coordinator.teardown()
        #expect(coordinator.hasActiveProvider == false)
        #expect(coordinator.isCloudActive == false)
        let tornDown = await apple.teardownCallCount
        #expect(tornDown == 1)

        // teardown 後は submit しても新規訳が入らない（入力 stream は finish 済み）。
        coordinator.submitConfirmed(TranslationInput(id: UUID(), text: "after", sourceTime: 1))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(coordinator.translations.count == 1)
    }

    // テスト7: teardown 冪等
    @Test("teardown() は冪等（複数回呼んでも provider.teardown は1回）")
    func teardownIdempotent() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .installed)),
            keychain: MockAPIKeyChecking(),
            appleProvider: apple,
            makeBYO: { _ in nil }
        )

        await coordinator.reconcile(ctx: ctx(privacy: false))
        let afterActivate = await apple.teardownCallCount
        #expect(afterActivate == 0)

        await coordinator.teardown()
        await coordinator.teardown()
        await coordinator.teardown()
        let count = await apple.teardownCallCount
        #expect(count == 1)
        #expect(coordinator.hasActiveProvider == false)
    }
}
