import SwiftUI

/// アプリの外観（テーマ）設定。
///
/// デザイン上の対応関係:
/// - `.light`  → Manuscript（冷たい紙・墨・朱）
/// - `.dark`   → Console（鎮めた計器・ティール1点）
/// - `.system` → OS の外観に追従（実効値に応じて上記いずれかへ解決）
enum SokkiAppearance: String, CaseIterable {
    case system
    case light
    case dark

    /// 設定 UI 向けの表示名。
    var displayName: String {
        switch self {
        case .system: return "システム"
        case .light:  return "ライト"
        case .dark:   return "ダーク"
        }
    }

    /// `preferredColorScheme(_:)` へ渡す値。`.system` は OS 追従のため nil。
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - 実効テーマからのトークン解決

extension SokkiTokens {
    /// 実効 `ColorScheme` からトークンセットを解決する。
    /// dark = Console、light = Manuscript。
    static func resolve(for colorScheme: ColorScheme) -> SokkiTokens {
        colorScheme == .dark ? .console : .manuscript
    }
}

// MARK: - ルート適用モディファイア

/// 外観設定（`@AppStorage`）と実効 `colorScheme` を読み、トークンを environment に注入したうえで
/// `preferredColorScheme` を適用する。アプリのルートビューに一度だけ付ける。
private struct SokkiDesignSystemModifier: ViewModifier {
    @AppStorage("sokki.appearance") private var appearance: SokkiAppearance = .system
    @Environment(\.colorScheme) private var systemColorScheme

    func body(content: Content) -> some View {
        // `.system` のときは環境（OS）の colorScheme を実効値とし、
        // それ以外は選択されたテーマをそのまま実効値とする。
        let effective = appearance.preferredColorScheme ?? systemColorScheme
        content
            .environment(\.sokkiTokens, SokkiTokens.resolve(for: effective))
            .preferredColorScheme(appearance.preferredColorScheme)
    }
}

extension View {
    /// デザインシステムを注入する。外観設定に応じてトークン（`\.sokkiTokens`）と
    /// カラースキームを確定する。アプリのルートビューに一度だけ適用する。
    func sokkiDesignSystem() -> some View {
        modifier(SokkiDesignSystemModifier())
    }
}
