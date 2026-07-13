import Foundation

/// `Locale.Language` を DeepL REST API の言語コードへ変換する純粋関数群。
///
/// DeepL は `source_lang` には地域変種を含まない言語コードのみを受け付けるが、
/// `target_lang` は以下について変種の明示を要求する（無変種のコードは非推奨・拒否されうる）:
/// - 英語: `EN-GB` / `EN-US`
/// - ポルトガル語: `PT-PT` / `PT-BR`
/// - 中国語: `ZH-HANS`（簡体字） / `ZH-HANT`（繁体字）
/// - スペイン語: `ES`（欧州） / `ES-419`（ラテンアメリカ、UN M49 リージョンコード）
/// 参照: DeepL API ドキュメント（`/v2/translate` の `source_lang`/`target_lang`、
/// `developers.deepl.com/api-reference/languages`）。
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
        let script = language.script?.identifier.uppercased()

        guard role == .target else { return languageCode }

        switch languageCode {
        case "EN":
            return region == "GB" ? "EN-GB" : "EN-US"
        case "PT":
            return region == "BR" ? "PT-BR" : "PT-PT"
        case "ZH":
            // script（Hans/Hant）明示、または繁体字/簡体字圏リージョンなら明示的に variant を
            // 返す。以前は Hant 明示（`zh-Hant` 等）でも無変種 `ZH` に潰れていたのが不具合。
            // 実務上 `Locale.Language(identifier: "zh")` は CLDR likely-subtags により
            // script が "Hans" に解決されるため、bare "zh" も通常 ZH-HANS に着地する。
            // script/region のどちらも取得できない異常系のみ、DeepL がなお受け付ける
            // 無変種 `ZH` にフォールバックする。
            if script == "HANT" || ["TW", "HK", "MO"].contains(region) {
                return "ZH-HANT"
            }
            if script == "HANS" || ["CN", "SG"].contains(region) {
                return "ZH-HANS"
            }
            return "ZH"
        case "ES":
            // "419" は UN M49 のラテンアメリカ・カリブ地域コード（DeepL の慣習）。
            return region == "419" ? "ES-419" : "ES"
        default:
            return languageCode
        }
    }
}
