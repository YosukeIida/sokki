import Foundation
import SwiftData

@Model
final class AppSettingsModel {
    @Attribute(.unique) var id: UUID = UUID()

    // LLM 設定
    var llmBaseURL: String?
    var llmApiKey: String?
    var llmModel: String?

    // エンジン設定
    var transcriptionEngine: String = "whisperkit"
    var whisperModelVariant: String = ""  // "" = auto-select (デバイス推奨モデル)
    var diarizationEnabled: Bool = true
    var numberOfSpeakers: Int = 0       // 0 = 自動

    // 声紋照合設定
    var embeddingMatchThreshold: Float = 0.82
    var embeddingEMAAlpha: Float = 0.1

    // 翻訳設定（TASK-20 / Phase2.5）。既定 OFF・プライバシーモード既定 ON。
    // `translationProvider` は `TranslationProviderKind.rawValue`。
    // `translationSourceLanguage`/`translationTargetLanguage` は BCP-47 相当の言語コード
    // 文字列。source の既定 "auto" は「文字起こし言語に追従」を意味し、
    // `TranslationSettingsMapper` が実際の `Locale.Language` へ解決する（source 明示 UI は
    // 後続タスク。doc `docs/translation-architecture.md` §14.4）。
    var translationEnabled: Bool = false
    var translationProvider: String = TranslationProviderKind.auto.rawValue
    var translationSourceLanguage: String = "auto"
    var translationTargetLanguage: String = "en"
    // クラウド送信を伴う自動フォールバックを抑止するプライバシーゲート（既定 ON）。
    // `TranslationGate.evaluate` の入力（`docs/translation-architecture.md` §5）。
    var privacyModeEnabled: Bool = true

    init() {}
}
