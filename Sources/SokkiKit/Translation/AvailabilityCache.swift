import Foundation
import Translation

/// Apple Translation の言語対応状況を照会する抽象。テスト注入可能にするための protocol。
///
/// 返す `LanguageAvailability.Status`（`.installed` / `.supported` / `.unsupported`）は
/// 値型で actor 境界を越えられる。非 Sendable な `LanguageAvailability` 本体は実装 actor
/// 内に封じ込める。
///
/// 注: doc §6 では `supportedLanguages()` も宣言していたが、`LanguageAvailability`
/// の該当メンバは `nonisolated` async であり、非 Sendable な本体を actor 外へ持ち出さずに
/// 呼ぶ手段が strict concurrency 下で無い（`@preconcurrency` は警告を生む）。ルーティングは
/// `status(from:to:)` だけで成立し、対応言語一覧は auto 言語検出（doc §14.4・後続フェーズ）
/// まで不要なため、ここでは宣言しない（§0 の「非 Sendable 封じ込め」を優先）。
public protocol AvailabilityChecking: Sendable {
    func status(from: Locale.Language, to: Locale.Language) async -> LanguageAvailability.Status
}

/// `LanguageAvailability` をラップし、対応状況をキャッシュする actor。
///
/// `LanguageAvailability` は非 Sendable。doc §6 は `let backing = LanguageAvailability()`
/// を actor に保持する形だったが、その保持済みインスタンスの `nonisolated async` メンバ
/// （`status(from:to:)`）を呼ぶと strict concurrency 下で「sending self.backing risks data
/// races」となりコンパイルできない。そこで **照会ごとにローカルで生成** し、切り離された
/// isolation region として合法に送る。非 Sendable インスタンスは actor 内の1呼び出しに
/// 閉じ、外へは値型 `Status` だけが出る（§12「非 Sendable 封じ込め」を厳密化）。
public actor AvailabilityCache: AvailabilityChecking {
    private var cache: [String: LanguageAvailability.Status] = [:]

    public init() {}

    private func key(_ from: Locale.Language, _ to: Locale.Language) -> String {
        "\(from.maximalIdentifier)->\(to.maximalIdentifier)"
    }

    public func status(
        from: Locale.Language,
        to: Locale.Language
    ) async -> LanguageAvailability.Status {
        let k = key(from, to)
        if let cached = cache[k] { return cached }
        // ローカル生成 → 切り離し region なので nonisolated メンバへ合法に送れる。
        let checker = LanguageAvailability()
        let s = await checker.status(from: from, to: to)
        cache[k] = s
        return s
    }

    /// 指定ペアのキャッシュを破棄（言語モデルの DL 完了後などに使う）。
    public func invalidate(from: Locale.Language, to: Locale.Language) {
        cache[key(from, to)] = nil
    }
}
