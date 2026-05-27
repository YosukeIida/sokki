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

    init() {}
}
