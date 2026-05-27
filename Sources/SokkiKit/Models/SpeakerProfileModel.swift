import Foundation
import SwiftData

@Model
final class SpeakerProfileModel {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var embeddingData: Data     // [Float] 256dim × 4 bytes = 1024 bytes
    var embeddingCount: Int
    var colorHex: String
    var createdAt: Date
    var lastSeenAt: Date

    @Relationship(deleteRule: .nullify, inverse: \SegmentModel.speakerProfile)
    var segments: [SegmentModel] = []

    init(displayName: String, embedding: [Float]) {
        self.id = UUID()
        self.displayName = displayName
        self.embeddingData = Self.serialize(embedding)
        self.embeddingCount = 1
        self.colorHex = SpeakerColorPalette.next()
        self.createdAt = .now
        self.lastSeenAt = .now
    }

    var embedding: [Float] {
        get { Self.deserialize(embeddingData) }
        set { embeddingData = Self.serialize(newValue) }
    }

    // 指数移動平均で更新（count > 10 になったら alpha を下げる予定）
    func updateEmbedding(with newEmbedding: [Float], alpha: Float = 0.1) {
        var current = embedding
        current = zip(current, newEmbedding).map { (1 - alpha) * $0 + alpha * $1 }
        embedding = l2Normalize(current)
        embeddingCount += 1
        lastSeenAt = .now
    }

    private static func serialize(_ v: [Float]) -> Data {
        v.withUnsafeBytes { Data($0) }
    }

    private static func deserialize(_ data: Data) -> [Float] {
        data.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }
    }
}

enum SpeakerColorPalette {
    private static let colors = [
        "#3B82F6",  // 青
        "#EF4444",  // 赤
        "#10B981",  // 緑
        "#F59E0B",  // 黄
        "#8B5CF6",  // 紫
        "#EC4899",  // ピンク
        "#06B6D4",  // シアン
        "#F97316",  // オレンジ
    ]
    nonisolated(unsafe) private static var index = 0

    static func next() -> String {
        let color = colors[index % colors.count]
        index += 1
        return color
    }
}
