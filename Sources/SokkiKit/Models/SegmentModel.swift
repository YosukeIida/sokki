import Foundation
import SwiftData

@Model
final class SegmentModel {
    @Attribute(.unique) var id: UUID
    var start: Double
    var end: Double
    var text: String
    var avgLogProb: Float
    var speakerLabel: String?           // "SPEAKER_00"（エンジン内部ラベル）

    var speakerProfile: SpeakerProfileModel?
    var session: SessionModel?

    init(start: Double, end: Double, text: String) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.text = text
        self.avgLogProb = 0
    }

    var speakerDisplayName: String {
        speakerProfile?.displayName ?? speakerLabel ?? "不明"
    }
}
