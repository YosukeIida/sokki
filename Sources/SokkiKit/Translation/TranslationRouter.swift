import Foundation
import Translation

/// ルーティングの入力スナップショット。
public struct RoutingContext: Sendable, Equatable {
    public let enabled: Bool
    /// ユーザー設定の希望プロバイダ（`auto` を含む）。
    public let preferred: TranslationProviderKind
    public let source: Locale.Language
    public let target: Locale.Language
    public let privacyMode: Bool
    /// アプリが実体化できる（＝ `makeBYO` で生成可能な）クラウド種別。**キー有無とは無関係**。
    /// Router はここに含まれる種別だけを auto フォールバック候補にする。キー未設定の拒否は
    /// Gate.missingApiKey が担う（`docs/translation-architecture.md` §0 訂正 #4）。
    public let registeredCloudKinds: Set<TranslationProviderKind>
    /// 自動フォールバックの試行順（登録済み種別のうち先頭が採用される）。
    public let cloudPreferenceOrder: [TranslationProviderKind]

    public init(
        enabled: Bool,
        preferred: TranslationProviderKind,
        source: Locale.Language,
        target: Locale.Language,
        privacyMode: Bool,
        registeredCloudKinds: Set<TranslationProviderKind>,
        cloudPreferenceOrder: [TranslationProviderKind]
    ) {
        self.enabled = enabled
        self.preferred = preferred
        self.source = source
        self.target = target
        self.privacyMode = privacyMode
        self.registeredCloudKinds = registeredCloudKinds
        self.cloudPreferenceOrder = cloudPreferenceOrder
    }
}

/// ルーティング結果。`auto` は解決済みの実体 `kind` になる。
public struct RoutingDecision: Sendable, Equatable {
    public let kind: TranslationProviderKind
    public let isOnDevice: Bool
    public let isUserExplicitChoice: Bool
    /// Apple `.supported`（DL 可能だが未 DL）。
    public let needsModelDownload: Bool
    /// ルート不能時の理由（`nil` = ルート確定）。
    public let unavailableReason: String?

    public init(
        kind: TranslationProviderKind,
        isOnDevice: Bool,
        isUserExplicitChoice: Bool,
        needsModelDownload: Bool,
        unavailableReason: String?
    ) {
        self.kind = kind
        self.isOnDevice = isOnDevice
        self.isUserExplicitChoice = isUserExplicitChoice
        self.needsModelDownload = needsModelDownload
        self.unavailableReason = unavailableReason
    }
}

/// 2段ルーティング（Tier1 Apple → Tier2 BYO 自動フォールバック）を担う actor。
///
/// 責務は **route の解決だけ**。**Router はキー有無を一切参照しない**（`docs/translation-architecture.md`
/// §0 訂正 #4）。auto フォールバックの候補選択は「登録済み（実体化可能な）クラウド種別」だけで
/// 行い、そのクラウドにキーが無い場合の拒否は下流の Gate.missingApiKey が担う。これにより
/// missing-key の判定源が Gate 一箇所に一本化され、Router が早期 return して Gate の
/// missingApiKey 経路を飛ばす drift が構造的に起きない。
public actor TranslationRouter {
    private let availability: any AvailabilityChecking

    public init(availability: any AvailabilityChecking) {
        self.availability = availability
    }

    public func resolve(_ ctx: RoutingContext) async -> RoutingDecision {
        guard ctx.enabled else {
            // disabled は Gate.toggleOff で弾く。ここでは無害な既定を返す。
            return RoutingDecision(
                kind: .auto, isOnDevice: true, isUserExplicitChoice: false,
                needsModelDownload: false, unavailableReason: nil
            )
        }

        // 1. ユーザー明示選択（auto 以外）。
        if ctx.preferred != .auto {
            if ctx.preferred == .apple {
                return await resolveApple(ctx, explicit: true)
            }
            // 明示 BYO: route だけ返す。key 有無は Gate.hasValidApiKey が判定する（#4）。
            return RoutingDecision(
                kind: ctx.preferred, isOnDevice: false, isUserExplicitChoice: true,
                needsModelDownload: false, unavailableReason: nil
            )
        }

        // 2. auto: まず Apple。
        let apple = await resolveApple(ctx, explicit: false)
        if apple.unavailableReason == nil { return apple }

        // 3. auto フォールバック: Apple 未対応 → 登録済みクラウドの先頭（キー有無は見ない）。
        //    キー未設定なら下流の Gate.missingApiKey が拒否する。
        let usable = ctx.cloudPreferenceOrder.first { ctx.registeredCloudKinds.contains($0) }
        guard let fallback = usable else {
            return RoutingDecision(
                kind: .auto, isOnDevice: true, isUserExplicitChoice: false,
                needsModelDownload: false,
                unavailableReason: "オンデバイス未対応。BYO 翻訳プロバイダが未登録です"
            )
        }
        return RoutingDecision(
            kind: fallback, isOnDevice: false, isUserExplicitChoice: false /* 自動FB */,
            needsModelDownload: false, unavailableReason: nil
        )
    }

    private func resolveApple(_ ctx: RoutingContext, explicit: Bool) async -> RoutingDecision {
        switch await availability.status(from: ctx.source, to: ctx.target) {
        case .installed:
            return RoutingDecision(
                kind: .apple, isOnDevice: true, isUserExplicitChoice: explicit,
                needsModelDownload: false, unavailableReason: nil
            )
        case .supported:
            return RoutingDecision(
                kind: .apple, isOnDevice: true, isUserExplicitChoice: explicit,
                needsModelDownload: true, unavailableReason: nil
            )
        case .unsupported:
            return RoutingDecision(
                kind: .apple, isOnDevice: true, isUserExplicitChoice: explicit,
                needsModelDownload: false, unavailableReason: "Apple 未対応の言語ペア"
            )
        @unknown default:
            // fail-closed: 不明な対応状況は不能扱い。
            return RoutingDecision(
                kind: .apple, isOnDevice: true, isUserExplicitChoice: explicit,
                needsModelDownload: false, unavailableReason: "不明な対応状況"
            )
        }
    }
}
