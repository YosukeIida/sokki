import Foundation

/// `Locale.Language` を DeepL REST API の言語コードへ変換する純粋関数群。
///
/// DeepL は `source_lang` には地域変種を含まない言語コードのみを受け付けるが、
/// `target_lang` は英語 (`EN-GB`/`EN-US`) とポルトガル語 (`PT-PT`/`PT-BR`) について
/// 地域変種の明示を要求する（無変種の `EN`/`PT` は非推奨・拒否されうる）。
/// 参照: DeepL API ドキュメント（`/v2/translate` の `source_lang`/`target_lang`）。
enum DeepLLanguageMapping {
    /// 言語コードの用途。source/target で許容される表現が異なるため区別する。
    enum Role: Sendable, Equatable {
        case source
        case target
    }

    /// 副作用なしの変換関数。`Locale.Language` の `languageCode` が取得できない異常系は
    /// フォールバックとして `"EN"` を返す（呼び出し側の `prepare()` は言語未指定を別途弾く）。
    static func code(for language: Locale.Language, role: Role) -> String {
        let languageCode = language.languageCode?.identifier.uppercased() ?? "EN"
        let region = language.region?.identifier.uppercased()

        guard role == .target else { return languageCode }

        switch languageCode {
        case "EN":
            return region == "GB" ? "EN-GB" : "EN-US"
        case "PT":
            return region == "BR" ? "PT-BR" : "PT-PT"
        default:
            return languageCode
        }
    }
}
