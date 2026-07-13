import Foundation

/// `TranslationGate.evaluate` の入力。副作用ゼロで評価するための値型スナップショット。
public struct TranslationGateContext: Sendable, Equatable {
    public let translationEnabled: Bool
    public let privacyModeEnabled: Bool
    public let providerIsOnDevice: Bool
    /// ユーザーが provider を明示選択したか（`auto` の自動フォールバックでないか）。
    public let isUserExplicitChoice: Bool
    /// Keychain 照会結果（存在チェックのみ。失効/無効キーは検出しない）。
    public let hasValidApiKey: Bool

    public init(
        translationEnabled: Bool,
        privacyModeEnabled: Bool,
        providerIsOnDevice: Bool,
        isUserExplicitChoice: Bool,
        hasValidApiKey: Bool
    ) {
        self.translationEnabled = translationEnabled
        self.privacyModeEnabled = privacyModeEnabled
        self.providerIsOnDevice = providerIsOnDevice
        self.isUserExplicitChoice = isUserExplicitChoice
        self.hasValidApiKey = hasValidApiKey
    }
}

/// ゲート判定結果。
public enum TranslationDecision: Sendable, Equatable {
    case allow
    case denied(DenyReason)

    public enum DenyReason: String, Sendable, Equatable {
        case toggleOff
        /// privacy ON + 自動フォールバックでのクラウド（越権防止）。
        case privacyBlocksAutoCloud
        case missingApiKey
    }
}

/// プライバシーゲート。クラウド送信可否を **単一の純粋関数** に一元化する（fail-closed）。
///
/// provider に権限判定を分散させない。監査点はこの関数ただ1つ。
/// 真理値表の全分岐はユニットテストで網羅する（`docs/translation-architecture.md` §5）。
public enum TranslationGate {
    /// 副作用なし・全分岐網羅。テストの主対象。
    public static func evaluate(_ c: TranslationGateContext) -> TranslationDecision {
        // 1. トグル最優先。
        guard c.translationEnabled else { return .denied(.toggleOff) }
        // 2. オンデバイスは常に許可（クラウド送信が起きない）。
        if c.providerIsOnDevice { return .allow }
        // --- 以下クラウドのみ到達 ---
        // 3. key 必須。
        guard c.hasValidApiKey else { return .denied(.missingApiKey) }
        // 4. プライバシーモードの扱い:
        //    - ユーザー明示選択 = オプトイン成立 → 許可
        //    - 自動フォールバック（auto から Apple 未対応で BYO に流れた）→ 越権なので拒否
        if c.privacyModeEnabled && !c.isUserExplicitChoice {
            return .denied(.privacyBlocksAutoCloud)
        }
        return .allow
    }
}
