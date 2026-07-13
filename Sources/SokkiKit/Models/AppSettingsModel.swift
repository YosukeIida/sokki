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
    // 文字起こし言語。"auto" = 自動検出（既定）。それ以外は ISO 639-1 言語コード（"ja", "en" 等）。
    var transcriptionLanguage: String = "auto"
    var diarizationEnabled: Bool = true
    var numberOfSpeakers: Int = 0       // 0 = 自動

    // 声紋照合設定
    var embeddingMatchThreshold: Float = 0.82
    var embeddingEMAAlpha: Float = 0.1

    // 会議自動検出設定（TASK-15）。SCShareableContent 呼び出し（画面収録権限プロンプト）を
    // 伴うため既定は false。true の間のみ RecordingView がポーリングを開始する。
    var meetingDetectionEnabled: Bool = false

    // 翻訳設定（TASK-20 / Phase2.5）。既定 OFF・プライバシーモード既定 ON。
    // `translationProvider` は `TranslationProviderKind.rawValue`。
    // `translationSourceLanguage`/`translationTargetLanguage` は BCP-47 相当の言語コード
    // 文字列。source の既定 "auto" は将来的に「文字起こし言語に追従」させる想定の予約値だが、
    // 真の自動検出は未実装（`TranslationSettingsMapper.resolveLocaleLanguage` が現時点では
    // 固定で "ja" にフォールバックする）。source 明示 UI・自動検出は後続タスク
    // （doc `docs/translation-architecture.md` §14.4 / TASK-20 レビュー指摘）。
    var translationEnabled: Bool = false
    var translationProvider: String = TranslationProviderKind.auto.rawValue
    var translationSourceLanguage: String = "auto"
    var translationTargetLanguage: String = "en"
    // クラウド送信を伴う自動フォールバックを抑止するプライバシーゲート（既定 ON）。
    // `TranslationGate.evaluate` の入力（`docs/translation-architecture.md` §5）。
    var privacyModeEnabled: Bool = true

    init() {}
}
