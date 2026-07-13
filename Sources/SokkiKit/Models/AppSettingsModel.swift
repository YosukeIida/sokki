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

    init() {}
}
