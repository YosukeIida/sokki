import Foundation
import ScreenCaptureKit

/// `SCShareableContent` の呼び出しをテスト用にモックできるようにする境界プロトコル。
/// 画面収録権限のプロンプトを実際に発生させるのはこの protocol の実装（`SCShareableContentProvider`）のみで、
/// テストでは差し替えた実装を使うことで実機権限に依存せずに検証できる。
protocol ShareableContentProviding: Sendable {
    /// 現在起動中のウィンドウ一覧を取得する。権限が無い場合などは throw する。
    func currentWindows() async throws -> [MeetingWindowInfo]
}

/// `SCShareableContent.current` を使った実装。
struct SCShareableContentProvider: ShareableContentProviding {
    func currentWindows() async throws -> [MeetingWindowInfo] {
        let content = try await SCShareableContent.current
        return content.windows.map {
            MeetingWindowInfo(
                bundleIdentifier: $0.owningApplication?.bundleIdentifier,
                title: $0.title
            )
        }
    }
}
