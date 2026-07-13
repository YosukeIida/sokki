import Testing
import Foundation
import Translation
@testable import SokkiKit

/// TASK-20 の DI 結線テスト。
///
/// `AppDependencyContainer` が実際に組み立てる部品（プレースホルダ provider/keychain +
/// `TranslationSettingsMapper`）を使い、OFF → ON → OFF の遷移で fail-closed 契約が
/// 保たれることを確認する。実 `AvailabilityCache`/Apple Translation フレームワークには
/// 依存しない（`MockAvailability` を注入）。
@Suite("翻訳 DI プレースホルダの結線")
@MainActor
struct TranslationDIWiringTests {

    @Test("PlaceholderAppleTranslationProvider は常に languagePairUnsupported を throw する")
    func placeholderAppleProviderAlwaysThrows() async {
        let provider = PlaceholderAppleTranslationProvider()
        #expect(provider.providerID == "apple")
        #expect(provider.isOnDevice == true)

        let ja = Locale.Language(identifier: "ja")
        let en = Locale.Language(identifier: "en")
        do {
            try await provider.prepare(source: ja, target: en)
            Issue.record("prepare が throw しなかった")
        } catch let error as TranslationProviderError {
            #expect(error == .languagePairUnsupported(
                source: ja.maximalIdentifier, target: en.maximalIdentifier
            ))
        } catch {
            Issue.record("想定外のエラー型: \(error)")
        }
    }

    @Test("PlaceholderAPIKeyChecking は常にキー無しを返す（TASK-23 前は fail-closed）")
    func placeholderAPIKeyCheckingHasNoKeys() {
        let checking = PlaceholderAPIKeyChecking()
        #expect(checking.hasKey(for: "googleCloudV3") == false)
        #expect(checking.hasKey(for: "geminiLive") == false)
        #expect(checking.hasKey(for: "apple") == false)
    }

    /// 設定 OFF → mapper → Coordinator.reconcile が inactive のままであること
    /// （AC#2: OFF 時はクラウド送信ゼロ）。
    @Test("設定 OFF から組み立てた RoutingContext は Coordinator を非アクティブのままにする")
    func offSettingsKeepCoordinatorInactive() async {
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .installed)),
            keychain: PlaceholderAPIKeyChecking(),
            appleProvider: PlaceholderAppleTranslationProvider(),
            makeBYO: { _ in nil }
        )
        let snapshot = TranslationSettingsSnapshot(
            translationEnabled: false,
            translationProvider: TranslationProviderKind.auto.rawValue,
            translationSourceLanguage: "auto",
            translationTargetLanguage: "en",
            privacyModeEnabled: true
        )
        let ctx = TranslationSettingsMapper.routingContext(from: snapshot, registeredCloudKinds: [])

        await coordinator.reconcile(ctx: ctx)

        #expect(coordinator.hasActiveProvider == false)
        #expect(coordinator.isCloudActive == false)
        #expect(coordinator.statusBanner == nil)   // toggleOff はバナー無し
    }

    /// 設定 OFF→ON→OFF の遷移。ON では Apple provider がプレースホルダのため実際には
    /// 起動できないが（TASK-18 未マージ）、fail-closed のまま推移し、最終的に OFF で
    /// teardown が反映されること。
    @Test("OFF → ON → OFF でも常に非アクティブ・fail-closed のまま推移する")
    func offOnOffTransitionStaysFailClosed() async {
        let coordinator = TranslationCoordinator(
            router: TranslationRouter(availability: MockAvailability(stub: .installed)),
            keychain: PlaceholderAPIKeyChecking(),
            appleProvider: PlaceholderAppleTranslationProvider(),
            makeBYO: { _ in nil }
        )

        func ctx(enabled: Bool) -> RoutingContext {
            TranslationSettingsMapper.routingContext(
                from: TranslationSettingsSnapshot(
                    translationEnabled: enabled,
                    translationProvider: TranslationProviderKind.auto.rawValue,
                    translationSourceLanguage: "auto",
                    translationTargetLanguage: "en",
                    privacyModeEnabled: true
                ),
                registeredCloudKinds: []
            )
        }

        // OFF
        await coordinator.reconcile(ctx: ctx(enabled: false))
        #expect(coordinator.hasActiveProvider == false)

        // ON: auto → Apple(.installed) → Gate.allow(onDevice) → activate → prepare が
        // プレースホルダの languagePairUnsupported で失敗 → fail-closed のまま。
        await coordinator.reconcile(ctx: ctx(enabled: true))
        #expect(coordinator.hasActiveProvider == false)
        #expect(coordinator.lastError != nil)

        // OFF に戻す → teardown 経路（既に非アクティブだが冪等に完了する）。
        await coordinator.reconcile(ctx: ctx(enabled: false))
        #expect(coordinator.hasActiveProvider == false)
        #expect(coordinator.isCloudActive == false)
        #expect(coordinator.statusBanner == nil)
    }
}
