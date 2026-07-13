import Foundation
import WhisperKit

/// 文字起こし言語の選択肢。AppSettingsModel.transcriptionLanguage の値（rawValue）として永続化する。
enum TranscriptionLanguageOption: String, CaseIterable, Sendable {
    case auto
    case japanese = "ja"
    case english = "en"
    case chinese = "zh"
    case korean = "ko"
    case spanish = "es"
    case german = "de"
    case french = "fr"

    var displayName: String {
        switch self {
        case .auto: return "自動検出"
        case .japanese: return "日本語"
        case .english: return "英語"
        case .chinese: return "中国語"
        case .korean: return "韓国語"
        case .spanish: return "スペイン語"
        case .german: return "ドイツ語"
        case .french: return "フランス語"
        }
    }
}

/// AppSettingsModel.transcriptionLanguage の値（"auto" / "ja" / ... または nil・不正値）を
/// WhisperKit の `DecodingOptions.language` に渡す値へ変換する純粋関数。
///
/// - 自動検出（"auto" / nil / 未知の値）の場合は nil を返す（Whisper 側の言語自動判定に委ねる）。
/// - それ以外は ISO 639-1 言語コードをそのまま返す。
func decodingLanguageCode(fromSettingValue value: String?) -> String? {
    guard let value, let option = TranscriptionLanguageOption(rawValue: value), option != .auto else {
        return nil
    }
    return option.rawValue
}

/// AppSettingsModel.transcriptionLanguage の値から、WhisperKit へ渡す DecodingOptions を組み立てる純粋関数。
///
/// `DecodingOptions` は `usePrefillPrompt` の既定 `true` に伴い `detectLanguage` の既定が `false` になるため、
/// language 未指定（自動検出）のときは `detectLanguage` を明示的に `true` にしないと
/// WhisperKit 側の言語自動判定が働かず `Constants.defaultLanguageCode`（"en"）に固定されてしまう。
/// テスト容易性のため WhisperKitEngine から切り出している。
func makeWhisperDecodingOptions(languageSetting: String?) -> DecodingOptions {
    let languageCode = decodingLanguageCode(fromSettingValue: languageSetting)
    return DecodingOptions(language: languageCode, detectLanguage: languageCode == nil)
}
