import Foundation
import SwiftData

@Model
final class SessionModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var audioFilePath: String    // URL.path（SwiftData は URL 非対応）
    var durationSeconds: Double
    var captureMode: String      // "mic" | "system" | "both" | "file"

    @Relationship(deleteRule: .cascade)
    var segments: [SegmentModel] = []

    init(title: String, audioFilePath: String, captureMode: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.audioFilePath = audioFilePath
        self.durationSeconds = 0
        self.captureMode = captureMode
    }

    var audioFileURL: URL? { URL(fileURLWithPath: audioFilePath) }

    var sortedSegments: [SegmentModel] {
        segments.sorted { $0.start < $1.start }
    }
}
