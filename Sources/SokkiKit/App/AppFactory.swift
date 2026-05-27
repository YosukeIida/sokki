import SwiftData

/// sokki アプリのモデルコンテナを生成するファクトリ関数
public func makeModelContainer() throws -> ModelContainer {
    try ModelContainer(
        for: SessionModel.self,
             SegmentModel.self,
             SpeakerProfileModel.self,
             AppSettingsModel.self
    )
}
