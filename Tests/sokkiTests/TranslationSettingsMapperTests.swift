import Testing
import Foundation
import Translation
@testable import SokkiKit

/// 設定値 → `RoutingContext` への変換（純粋関数）のテスト。
///
/// `TranslationSettingsMapper` は非同期処理・実 API 依存を一切持たないため、
/// 実機や `AvailabilityCache` なしで全分岐を検証できる。
@Suite("TranslationSettingsMapper 設定値 → RoutingContext")
struct TranslationSettingsMapperTests {

    private func snapshot(
        enabled: Bool = false,
        provider: String = TranslationProviderKind.auto.rawValue,
        source: String = "auto",
        target: String = "en",
        privacy: Bool = true
    ) -> TranslationSettingsSnapshot {
        TranslationSettingsSnapshot(
            translationEnabled: enabled,
            translationProvider: provider,
            translationSourceLanguage: source,
            translationTargetLanguage: target,
            privacyModeEnabled: privacy
        )
    }

    @Test("AppSettingsModel の既定値相当（OFF・auto・source auto・target en・privacy ON）を変換する")
    func defaultsMapCorrectly() {
        let ctx = TranslationSettingsMapper.routingContext(
            from: snapshot(),
            registeredCloudKinds: []
        )
        #expect(ctx.enabled == false)
        #expect(ctx.preferred == .auto)
        #expect(ctx.source == Locale.Language(identifier: "ja"))   // "auto" → source fallback
        #expect(ctx.target == Locale.Language(identifier: "en"))
        #expect(ctx.privacyMode == true)
        #expect(ctx.registeredCloudKinds.isEmpty)
    }

    @Test("translationProvider の rawValue が明示プロバイダへ解決される")
    func explicitProviderResolves() {
        let ctx = TranslationSettingsMapper.routingContext(
            from: snapshot(provider: TranslationProviderKind.geminiLive.rawValue),
            registeredCloudKinds: [.geminiLive]
        )
        #expect(ctx.preferred == .geminiLive)
        #expect(ctx.registeredCloudKinds == [.geminiLive])
    }

    @Test("不正な rawValue は auto にフェイルセーフする")
    func invalidProviderFallsBackToAuto() {
        let ctx = TranslationSettingsMapper.routingContext(
            from: snapshot(provider: "no-such-provider"),
            registeredCloudKinds: []
        )
        #expect(ctx.preferred == .auto)
    }

    /// D-18（DeepL 撤去）の回帰テスト。撤去以前に `translationProvider = "deepL"` が
    /// 永続化されたユーザー設定を読み込んでも、`TranslationProviderKind(rawValue:)` が
    /// `nil` を返して `.auto` にフォールバックすること（クラッシュ・fail-open しない）。
    @Test("撤去済み 'deepL' の永続化済み rawValue は auto にフェイルセーフする（D-18 回帰）")
    func removedDeepLProviderFallsBackToAuto() {
        let ctx = TranslationSettingsMapper.routingContext(
            from: snapshot(provider: "deepL"),
            registeredCloudKinds: []
        )
        #expect(ctx.preferred == .auto)
    }

    @Test("source が明示指定されている場合は fallback を使わない")
    func explicitSourceIsUsedAsIs() {
        let ctx = TranslationSettingsMapper.routingContext(
            from: snapshot(source: "en"),
            registeredCloudKinds: []
        )
        #expect(ctx.source == Locale.Language(identifier: "en"))
    }

    @Test("target 言語コードがそのまま解決される")
    func targetLanguageResolves() {
        let ctx = TranslationSettingsMapper.routingContext(
            from: snapshot(target: "zh-Hans"),
            registeredCloudKinds: []
        )
        #expect(ctx.target == Locale.Language(identifier: "zh-Hans"))
    }

    @Test("privacyModeEnabled がそのまま透過する")
    func privacyModePassesThrough() {
        let ctxOn = TranslationSettingsMapper.routingContext(from: snapshot(privacy: true), registeredCloudKinds: [])
        let ctxOff = TranslationSettingsMapper.routingContext(from: snapshot(privacy: false), registeredCloudKinds: [])
        #expect(ctxOn.privacyMode == true)
        #expect(ctxOff.privacyMode == false)
    }

    @Test("cloudPreferenceOrder は既定でも明示指定でも反映される")
    func cloudPreferenceOrderIsForwarded() {
        let ctxDefault = TranslationSettingsMapper.routingContext(from: snapshot(), registeredCloudKinds: [])
        #expect(ctxDefault.cloudPreferenceOrder == TranslationSettingsMapper.defaultCloudPreferenceOrder)

        let ctxCustom = TranslationSettingsMapper.routingContext(
            from: snapshot(), registeredCloudKinds: [], cloudPreferenceOrder: [.geminiLive]
        )
        #expect(ctxCustom.cloudPreferenceOrder == [.geminiLive])
    }
}
