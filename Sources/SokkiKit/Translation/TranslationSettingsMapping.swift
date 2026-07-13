import Foundation

/// UI（`AppSettingsModel`）の翻訳設定を切り出した Sendable スナップショット。
///
/// `@Model` インスタンスは actor 境界を越えて渡せない（`CLAUDE.md` の既存方針）ため、
/// MainActor 上で読み取った値をここへコピーしてから純粋関数 `TranslationSettingsMapper`
/// に渡す。テストでも `AppSettingsModel` を介さずこの値型だけで組み立てられる。
public struct TranslationSettingsSnapshot: Sendable, Equatable {
    public let translationEnabled: Bool
    /// `TranslationProviderKind.rawValue`。不正な値は `TranslationSettingsMapper` が
    /// `.auto` にフォールバックする。
    public let translationProvider: String
    /// BCP-47 相当の言語コード。`"auto"` は将来「文字起こし言語に追従」させる想定の予約値だが、
    /// 現時点では `TranslationSettingsMapper.resolveLocaleLanguage` が固定で "ja" に
    /// フォールバックする（真の自動検出は未実装。後続フェーズ）。
    public let translationSourceLanguage: String
    public let translationTargetLanguage: String
    public let privacyModeEnabled: Bool

    public init(
        translationEnabled: Bool,
        translationProvider: String,
        translationSourceLanguage: String,
        translationTargetLanguage: String,
        privacyModeEnabled: Bool
    ) {
        self.translationEnabled = translationEnabled
        self.translationProvider = translationProvider
        self.translationSourceLanguage = translationSourceLanguage
        self.translationTargetLanguage = translationTargetLanguage
        self.privacyModeEnabled = privacyModeEnabled
    }

    // `AppSettingsModel` は internal 型のため、この便利イニシャライザも internal に留める。
    init(_ settings: AppSettingsModel) {
        self.init(
            translationEnabled: settings.translationEnabled,
            translationProvider: settings.translationProvider,
            translationSourceLanguage: settings.translationSourceLanguage,
            translationTargetLanguage: settings.translationTargetLanguage,
            privacyModeEnabled: settings.privacyModeEnabled
        )
    }
}

/// 設定値 → `RoutingContext` の変換を担う純粋関数群。
///
/// 副作用・非同期処理は一切持たない（実機・Translation フレームワーク非依存でテスト可能）。
/// `TranslationGateContext` は `RoutingDecision`（Router の非同期解決結果）に依存するため
/// ここでは組み立てない（`TranslationCoordinator.reconcile` が担う。
/// `docs/translation-architecture.md` §7）。
public enum TranslationSettingsMapper {
    /// auto フォールバックの既定試行順。Google Cloud v3 は OAuth2 未実装のため後回し
    /// （`docs/translation-architecture.md` §0 訂正 #8 / backlog TASK-22）。
    public static let defaultCloudPreferenceOrder: [TranslationProviderKind] = [
        .deepL, .geminiLive, .googleCloudV3,
    ]

    /// 設定スナップショットを `TranslationRouter.resolve` の入力へ変換する。
    ///
    /// - Parameters:
    ///   - registeredCloudKinds: アプリが実体化できる（= DI の `makeBYO` が非 nil を返す）
    ///     クラウド種別。キー有無とは無関係（Router はキーを見ない。Gate が判定する）。
    ///   - cloudPreferenceOrder: auto フォールバックの試行順。
    public static func routingContext(
        from snapshot: TranslationSettingsSnapshot,
        registeredCloudKinds: Set<TranslationProviderKind>,
        cloudPreferenceOrder: [TranslationProviderKind] = defaultCloudPreferenceOrder
    ) -> RoutingContext {
        RoutingContext(
            enabled: snapshot.translationEnabled,
            preferred: TranslationProviderKind(rawValue: snapshot.translationProvider) ?? .auto,
            source: resolveLocaleLanguage(
                snapshot.translationSourceLanguage, fallback: "ja"
            ),
            target: resolveLocaleLanguage(
                snapshot.translationTargetLanguage, fallback: "en"
            ),
            privacyMode: snapshot.privacyModeEnabled,
            registeredCloudKinds: registeredCloudKinds,
            cloudPreferenceOrder: cloudPreferenceOrder
        )
    }

    /// 保存済み言語コード文字列を `Locale.Language` へ解決する。
    ///
    /// `"auto"`（source の既定値）は `fallback` に解決する。真の自動言語検出は未実装
    /// （`docs/translation-architecture.md` §14.4: `LanguageAvailability.status(from:to:)`
    /// は source 必須のため、検出は後続フェーズ）。
    static func resolveLocaleLanguage(_ code: String, fallback: String) -> Locale.Language {
        let resolved = code == "auto" ? fallback : code
        return Locale.Language(identifier: resolved)
    }
}
