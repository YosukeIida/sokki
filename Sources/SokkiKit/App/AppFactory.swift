import Foundation
import SwiftData

/// sokki アプリのモデルコンテナを生成するファクトリ関数。
///
/// XCUITest（実機マイクを使う E2E）が production の SwiftData ストアを汚染しないよう、
/// 環境変数 `SOKKI_UITEST_STORE_URL` が設定されている場合はそのパスのストアを使う。
public func makeModelContainer() throws -> ModelContainer {
    if let storeURLPath = ProcessInfo.processInfo.environment["SOKKI_UITEST_STORE_URL"] {
        let config = ModelConfiguration(url: URL(fileURLWithPath: storeURLPath))
        return try ModelContainer(
            for: SessionModel.self,
                 SegmentModel.self,
                 SpeakerProfileModel.self,
                 AppSettingsModel.self,
            configurations: config
        )
    }
    return try ModelContainer(
        for: SessionModel.self,
             SegmentModel.self,
             SpeakerProfileModel.self,
             AppSettingsModel.self
    )
}
