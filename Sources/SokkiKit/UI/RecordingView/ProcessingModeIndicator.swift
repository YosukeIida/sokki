import Foundation

/// 録音画面の「ローカル処理 / API 使用中」バッジ状態（TASK-36）。
///
/// 文字起こし（WhisperKit / SpeechAnalyzer）は常にオンデバイスで実行されるため、
/// バッジの表示は翻訳のクラウド利用有無（`TranslationCoordinator.isCloudActive`）
/// だけで決まる。View から状態決定ロジックを切り出した純粋関数として、
/// SwiftUI に依存せずテストできるようにする。
enum ProcessingModeIndicator: Equatable {
    /// 翻訳が無効、またはオンデバイス翻訳のみ使用中（プライバシーモード ON 相当）。
    case local
    /// クラウド翻訳プロバイダが active（`isCloudActive == true`）。
    case cloudAPI

    /// `TranslationCoordinator.isCloudActive` から表示すべきバッジ種別を決める純粋関数。
    static func current(isCloudActive: Bool) -> ProcessingModeIndicator {
        isCloudActive ? .cloudAPI : .local
    }

    var label: String {
        switch self {
        case .local: return "ローカル処理"
        case .cloudAPI: return "API 使用中"
        }
    }

    var systemImage: String {
        switch self {
        case .local: return "checkmark.shield.fill"
        case .cloudAPI: return "cloud.fill"
        }
    }
}
