import Testing
import WhisperKit
@testable import SokkiKit

@Suite("TranscriptionLanguage")
struct TranscriptionLanguageTests {

    @Test("auto は DecodingOptions.language 用に nil へ変換される（自動検出）")
    func autoMapsToNil() {
        #expect(decodingLanguageCode(fromSettingValue: "auto") == nil)
    }

    @Test("nil は nil へ変換される（自動検出）")
    func nilMapsToNil() {
        #expect(decodingLanguageCode(fromSettingValue: nil) == nil)
    }

    @Test("未知の値は nil へフォールバックする（自動検出）")
    func unknownValueFallsBackToNil() {
        #expect(decodingLanguageCode(fromSettingValue: "not-a-language") == nil)
        #expect(decodingLanguageCode(fromSettingValue: "") == nil)
    }

    @Test("日本語固定は \"ja\" へ変換される")
    func japaneseMapsToJa() {
        #expect(decodingLanguageCode(fromSettingValue: "ja") == "ja")
    }

    @Test("英語固定は \"en\" へ変換される")
    func englishMapsToEn() {
        #expect(decodingLanguageCode(fromSettingValue: "en") == "en")
    }

    @Test("サポートする各言語コードがそのまま変換される", arguments: [
        "zh", "ko", "es", "de", "fr",
    ])
    func supportedLanguageCodesRoundTrip(code: String) {
        #expect(decodingLanguageCode(fromSettingValue: code) == code)
    }

    @Test("TranscriptionLanguageOption の全ケースに表示名が設定されている")
    func allCasesHaveDisplayName() {
        for option in TranscriptionLanguageOption.allCases {
            #expect(!option.displayName.isEmpty)
        }
    }

    @Test("TranscriptionLanguageOption.auto の rawValue は \"auto\"")
    func autoRawValue() {
        #expect(TranscriptionLanguageOption.auto.rawValue == "auto")
    }

    // MARK: - makeWhisperDecodingOptions
    //
    // DecodingOptions は usePrefillPrompt の既定 true に伴い detectLanguage の既定が false になるため、
    // language が nil のときに detectLanguage を明示的に true にしないと WhisperKit の言語自動判定が
    // 働かず "en" 固定になってしまう（実際に踏んだ回帰）。ここではその配線を直接検証する。

    @Test("自動検出設定では language が nil かつ detectLanguage が true になる")
    func autoBuildsDetectLanguageOptions() {
        let options = makeWhisperDecodingOptions(languageSetting: "auto")
        #expect(options.language == nil)
        #expect(options.detectLanguage == true)
    }

    @Test("未設定（nil）でも language が nil かつ detectLanguage が true になる")
    func nilSettingBuildsDetectLanguageOptions() {
        let options = makeWhisperDecodingOptions(languageSetting: nil)
        #expect(options.language == nil)
        #expect(options.detectLanguage == true)
    }

    @Test("日本語固定設定では language が \"ja\" かつ detectLanguage が false になる")
    func japaneseBuildsFixedLanguageOptions() {
        let options = makeWhisperDecodingOptions(languageSetting: "ja")
        #expect(options.language == "ja")
        #expect(options.detectLanguage == false)
    }

    @Test("英語固定設定では language が \"en\" かつ detectLanguage が false になる")
    func englishBuildsFixedLanguageOptions() {
        let options = makeWhisperDecodingOptions(languageSetting: "en")
        #expect(options.language == "en")
        #expect(options.detectLanguage == false)
    }
}
