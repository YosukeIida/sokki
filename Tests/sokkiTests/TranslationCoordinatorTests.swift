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
        registered: Set<TranslationProviderKind> = [],
        order: [TranslationProviderKind] = []
    ) -> RoutingContext {
        RoutingContext(
            enabled: true, preferred: preferred, source: ja, target: en,
            privacyMode: privacy, registeredCloudKinds: registered, cloudPreferenceOrder: order
        )
    }

    /// 条件が満たされるまで（または timeout まで）MainActor を明け渡して待つ。
    private func waitUntil(timeout: Duration = .seconds(3), _ cond: () async -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await cond()) && clock.now < deadline {
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

        await coordinator.reconcile(ctx: ctx(privacy: true, registered: [.deepL], order: [.deepL]))

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
        await coordinator.reconcile(ctx: ctx(privacy: false, registered: [.deepL], order: [.deepL]))
        #expect(coordinator.hasActiveProvider == true)
        #expect(coordinator.isCloudActive == true)
        let preparedBefore = await cloud.prepareCallCount
        #expect(preparedBefore == 1)

        // privacy ON に反転 → reconcile 冒頭の teardown で閉じ、Gate で denied
        await coordinator.reconcile(ctx: ctx(privacy: true, registered: [.deepL], order: [.deepL]))
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

    // MAJOR-2: auto 経路でも Gate.missingApiKey が実際に到達可能であることを示す。
    @Test("auto + Apple 未対応 + 登録済みだが key なし → Gate.missingApiKey で拒否（クラウド prepare されない）")
    func autoMissingKeyReachesGate() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true)
        let cloud = MockTranslationProvider(providerID: "deepL", isOnDevice: false)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .unsupported)),
            keychain: MockAPIKeyChecking(keys: []),   // key なし
            appleProvider: apple,
            makeBYO: { _ in cloud }
        )

        // privacy OFF なので privacyBlocksAutoCloud ではなく missingApiKey へ到達する。
        await coordinator.reconcile(ctx: ctx(privacy: false, registered: [.deepL], order: [.deepL]))

        #expect(coordinator.hasActiveProvider == false)
        #expect(coordinator.isCloudActive == false)
        let prepared = await cloud.prepareCallCount
        #expect(prepared == 0)
        #expect(coordinator.statusBanner == "BYO の API キーを設定してください")
    }

    // MAJOR-3: クラウド decision で factory 未登録なら appleProvider へ暗黙フォールバックせず fail-closed。
    @Test("クラウド decision で factory 未登録 → appleProvider に流れず fail-closed")
    func unregisteredCloudFactoryFailsClosed() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .unsupported)),
            keychain: MockAPIKeyChecking(keys: ["deepL"]),   // key はある（Gate は allow）
            appleProvider: apple,
            makeBYO: { _ in nil }                            // factory 未登録
        )

        await coordinator.reconcile(ctx: ctx(privacy: false, registered: [.deepL], order: [.deepL]))

        #expect(coordinator.hasActiveProvider == false)   // appleProvider へ暗黙フォールバックしない
        #expect(coordinator.isCloudActive == false)
        #expect(coordinator.lastError != nil)
        let applePrepared = await apple.prepareCallCount
        #expect(applePrepared == 0)                        // appleProvider も起動しない
    }

    // BLOCKER 回帰: prepare 実行中に privacy ON reconcile が完了しても、旧クラウド経路が
    // 復帰して active にならない（世代トークンで作りかけ provider を破棄）。
    @Test("prepare 中に privacy ON が完了しても旧クラウド経路は active にならない")
    func preparePreemptedByPrivacyOn() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true)
        let blocking = BlockingTranslationProvider(providerID: "deepL", isOnDevice: false)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .unsupported)),
            keychain: MockAPIKeyChecking(keys: ["deepL"]),
            appleProvider: apple,
            makeBYO: { _ in blocking }
        )

        // privacy OFF で reconcile 開始 → activate → blocking.prepare で停止。
        let first = Task {
            await coordinator.reconcile(ctx: ctx(privacy: false, registered: [.deepL], order: [.deepL]))
        }
        await waitUntil { await blocking.prepareStarted }

        // privacy ON reconcile を完了させ、世代を進める（denied）。
        await coordinator.reconcile(ctx: ctx(privacy: true, registered: [.deepL], order: [.deepL]))
        #expect(coordinator.hasActiveProvider == false)
        #expect(coordinator.statusBanner == "プライバシーモードのため自動クラウド翻訳は無効です")

        // 停止していた prepare を復帰させる → 旧経路が復帰しても active にしてはならない。
        await blocking.releasePrepare()
        await first.value

        #expect(coordinator.hasActiveProvider == false)   // ← BLOCKER: クラウド起動しない
        #expect(coordinator.isCloudActive == false)
        let tears = await blocking.teardownCallCount
        #expect(tears >= 1)                                // 作りかけ provider は teardown される
    }
}
