import Testing
import Foundation
@testable import SokkiKit

@Suite("ProcessingModeIndicator バッジ状態決定（TASK-36）")
struct ProcessingModeIndicatorTests {

    @Test("isCloudActive == false → ローカル処理バッジ")
    func localWhenCloudInactive() {
        let mode = ProcessingModeIndicator.current(isCloudActive: false)
        #expect(mode == .local)
        #expect(mode.label == "ローカル処理")
        #expect(mode.systemImage == "checkmark.shield.fill")
    }

    @Test("isCloudActive == true → API 使用中バッジ")
    func cloudAPIWhenCloudActive() {
        let mode = ProcessingModeIndicator.current(isCloudActive: true)
        #expect(mode == .cloudAPI)
        #expect(mode.label == "API 使用中")
        #expect(mode.systemImage == "cloud.fill")
    }

    private let ja = Locale.Language(identifier: "ja")
    private let en = Locale.Language(identifier: "en")

    private func ctx(privacy: Bool) -> RoutingContext {
        RoutingContext(
            enabled: true, preferred: .auto, source: ja, target: en,
            privacyMode: privacy, registeredCloudKinds: [.geminiLive], cloudPreferenceOrder: [.geminiLive]
        )
    }

    /// `TranslationCoordinator.isCloudActive` の実際の遷移から `ProcessingModeIndicator` を
    /// 導出する連動テスト（View ではなくバッジ状態を決める純粋関数側を検証する）。
    @Test("Coordinator が cloud active になるとバッジが API 使用中へ切り替わる")
    @MainActor
    func badgeFollowsCoordinatorCloudActive() async {
        let apple = MockTranslationProvider(providerID: "apple", isOnDevice: true)
        let cloud = MockTranslationProvider(providerID: "geminiLive", isOnDevice: false)
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .unsupported)),
            keychain: MockAPIKeyChecking(keys: ["geminiLive"]),
            appleProvider: apple,
            makeBYO: { _ in cloud }
        )

        // privacy OFF → auto ルーティングでクラウド provider が activate される。
        await coordinator.reconcile(ctx: ctx(privacy: false))
        #expect(ProcessingModeIndicator.current(isCloudActive: coordinator.isCloudActive) == .cloudAPI)

        // privacy ON に反転 → reconcile 冒頭の teardown でクラウドが閉じ、ローカル表示へ戻る。
        await coordinator.reconcile(ctx: ctx(privacy: true))
        #expect(ProcessingModeIndicator.current(isCloudActive: coordinator.isCloudActive) == .local)
    }
}
