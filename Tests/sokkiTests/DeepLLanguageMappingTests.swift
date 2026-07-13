import Testing
import Foundation
@testable import SokkiKit

@Suite("DeepLLanguageMapping 言語コード変換（純粋関数）")
struct DeepLLanguageMappingTests {

    @Test("source: 地域変種を含む言語も言語コードのみへ丸める")
    func sourcePlainLanguageCode() {
        let ja = Locale.Language(identifier: "ja")
        let enUS = Locale.Language(identifier: "en-US")
        #expect(DeepLLanguageMapping.code(for: ja, role: .source) == "JA")
        #expect(DeepLLanguageMapping.code(for: enUS, role: .source) == "EN")
    }

    @Test("target: 英語は地域指定なしなら EN-US へフォールバック")
    func targetEnglishDefaultsToUS() {
        let en = Locale.Language(identifier: "en")
        #expect(DeepLLanguageMapping.code(for: en, role: .target) == "EN-US")
    }

    @Test("target: en-GB は EN-GB")
    func targetEnglishGB() {
        let enGB = Locale.Language(identifier: "en-GB")
        #expect(DeepLLanguageMapping.code(for: enGB, role: .target) == "EN-GB")
    }

    @Test("target: en-US は EN-US")
    func targetEnglishUS() {
        let enUS = Locale.Language(identifier: "en-US")
        #expect(DeepLLanguageMapping.code(for: enUS, role: .target) == "EN-US")
    }

    @Test("target: ポルトガル語は地域指定なしなら PT-PT へフォールバック")
    func targetPortugueseDefaultsToPT() {
        let pt = Locale.Language(identifier: "pt")
        #expect(DeepLLanguageMapping.code(for: pt, role: .target) == "PT-PT")
    }

    @Test("target: pt-BR は PT-BR")
    func targetPortugueseBR() {
        let ptBR = Locale.Language(identifier: "pt-BR")
        #expect(DeepLLanguageMapping.code(for: ptBR, role: .target) == "PT-BR")
    }

    @Test("target: 地域変種が不要な言語はそのまま言語コード")
    func targetPlainLanguageCode() {
        let ja = Locale.Language(identifier: "ja")
        #expect(DeepLLanguageMapping.code(for: ja, role: .target) == "JA")
    }

    // MARK: - 中国語（script/region による繁体字・簡体字の判定）

    @Test("target: zh-Hant（script 明示）は ZH-HANT")
    func targetChineseTraditionalByScript() {
        let zhHant = Locale.Language(identifier: "zh-Hant")
        #expect(DeepLLanguageMapping.code(for: zhHant, role: .target) == "ZH-HANT")
    }

    @Test("target: zh-TW（繁体字圏リージョン）は ZH-HANT")
    func targetChineseTraditionalByRegion() {
        let zhTW = Locale.Language(identifier: "zh-TW")
        #expect(DeepLLanguageMapping.code(for: zhTW, role: .target) == "ZH-HANT")
    }

    @Test("target: zh-Hans（script 明示）は ZH-HANS")
    func targetChineseSimplifiedByScript() {
        let zhHans = Locale.Language(identifier: "zh-Hans")
        #expect(DeepLLanguageMapping.code(for: zhHans, role: .target) == "ZH-HANS")
    }

    @Test("target: zh-CN（簡体字圏リージョン）は ZH-HANS")
    func targetChineseSimplifiedByRegion() {
        let zhCN = Locale.Language(identifier: "zh-CN")
        #expect(DeepLLanguageMapping.code(for: zhCN, role: .target) == "ZH-HANS")
    }

    @Test("target: 変種指定なしの zh は Foundation の likely-subtags 解決で ZH-HANS になる")
    func targetChineseUnspecifiedResolvesToSimplified() {
        // `Locale.Language(identifier: "zh").script` は CLDR likely-subtags により
        // 明示指定なしでも "Hans" に解決される（bare "zh" の実務上の既定は簡体字）。
        let zh = Locale.Language(identifier: "zh")
        #expect(DeepLLanguageMapping.code(for: zh, role: .target) == "ZH-HANS")
    }

    // MARK: - スペイン語（ラテンアメリカ variant）

    @Test("target: es-419 は ES-419")
    func targetSpanishLatinAmerica() {
        let es419 = Locale.Language(identifier: "es-419")
        #expect(DeepLLanguageMapping.code(for: es419, role: .target) == "ES-419")
    }

    @Test("target: 地域指定なしの es は ES のまま")
    func targetSpanishDefaultsToPlain() {
        let es = Locale.Language(identifier: "es")
        #expect(DeepLLanguageMapping.code(for: es, role: .target) == "ES")
    }
}
