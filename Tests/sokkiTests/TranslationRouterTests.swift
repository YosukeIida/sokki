import Testing
import Foundation
import Translation
@testable import SokkiKit

@Suite("TranslationRouter 2段ルーティング")
struct TranslationRouterTests {

    private let ja = Locale.Language(identifier: "ja")
    private let en = Locale.Language(identifier: "en")

    private func ctx(
        enabled: Bool = true,
        preferred: TranslationProviderKind = .auto,
        privacy: Bool = false,
        keys: Set<TranslationProviderKind> = [],
        order: [TranslationProviderKind] = [.geminiLive, .googleCloudV3, .deepL]
    ) -> RoutingContext {
        RoutingContext(
            enabled: enabled,
            preferred: preferred,
            source: ja,
            target: en,
            privacyMode: privacy,
            availableKeys: keys,
            cloudPreferenceOrder: order
        )
    }

    private func router(_ status: LanguageAvailability.Status) -> TranslationRouter {
        TranslationRouter(availability: MockAvailability(stub: status))
    }

    @Test("disabled は無害な既定を返す（Gate.toggleOff で弾く前提）")
    func disabled() async {
        let d = await router(.unsupported).resolve(ctx(enabled: false))
        #expect(d.unavailableReason == nil)
        #expect(d.isOnDevice == true)
    }

    @Test("明示 apple + installed → apple 採用（DL 不要）")
    func explicitAppleInstalled() async {
        let d = await router(.installed).resolve(ctx(preferred: .apple))
        #expect(d.kind == .apple)
        #expect(d.isOnDevice == true)
        #expect(d.isUserExplicitChoice == true)
        #expect(d.needsModelDownload == false)
        #expect(d.unavailableReason == nil)
    }

    @Test("明示 apple + supported → DL 必要")
    func explicitAppleSupported() async {
        let d = await router(.supported).resolve(ctx(preferred: .apple))
        #expect(d.kind == .apple)
        #expect(d.needsModelDownload == true)
        #expect(d.unavailableReason == nil)
    }

    @Test("明示 apple + unsupported → 不能理由あり（fail-closed）")
    func explicitAppleUnsupported() async {
        let d = await router(.unsupported).resolve(ctx(preferred: .apple))
        #expect(d.kind == .apple)
        #expect(d.unavailableReason == "Apple 未対応の言語ペア")
    }

    @Test("明示 BYO は key の有無に依らず route だけ返す（#4: key 判定は Gate）")
    func explicitBYORouteOnly() async {
        // key なし
        let noKey = await router(.installed).resolve(ctx(preferred: .deepL, keys: []))
        #expect(noKey.kind == .deepL)
        #expect(noKey.isOnDevice == false)
        #expect(noKey.isUserExplicitChoice == true)
        #expect(noKey.unavailableReason == nil)   // Router は「APIキー未設定」を返さない
        // key あり
        let withKey = await router(.installed).resolve(ctx(preferred: .deepL, keys: [.deepL]))
        #expect(withKey.unavailableReason == nil)
    }

    @Test("auto + Apple installed → Apple 採用（自動FBに行かない）")
    func autoAppleAdopted() async {
        let d = await router(.installed).resolve(ctx(preferred: .auto))
        #expect(d.kind == .apple)
        #expect(d.isUserExplicitChoice == false)
        #expect(d.unavailableReason == nil)
    }

    @Test("auto + Apple 未対応 + key あり → 優先順の先頭クラウドへ自動FB（explicit=false）")
    func autoFallbackToCloud() async {
        let d = await router(.unsupported).resolve(
            ctx(preferred: .auto, keys: [.googleCloudV3, .deepL],
                order: [.geminiLive, .googleCloudV3, .deepL])
        )
        // geminiLive は key 無し → 次の googleCloudV3 が選ばれる
        #expect(d.kind == .googleCloudV3)
        #expect(d.isOnDevice == false)
        #expect(d.isUserExplicitChoice == false)   // 自動FB は明示選択ではない
        #expect(d.unavailableReason == nil)
    }

    @Test("auto + Apple 未対応 + key なし → 不能（原文のみ）")
    func autoFallbackNoKey() async {
        let d = await router(.unsupported).resolve(ctx(preferred: .auto, keys: []))
        #expect(d.isOnDevice == true)
        #expect(d.unavailableReason == "オンデバイス未対応。BYO キーを設定すると翻訳できます")
    }
}
