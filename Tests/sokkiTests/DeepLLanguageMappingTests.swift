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
}
