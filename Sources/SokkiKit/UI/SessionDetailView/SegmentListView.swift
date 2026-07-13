import SwiftUI

struct SegmentListView: View {
    let session: SessionModel
    /// 再生コントローラ（TASK-33）。音声ファイルが存在しない場合は nil にして
    /// クリックでの再生ジャンプ・ハイライトを無効化する。
    var playback: AudioPlaybackController?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(session.sortedSegments.enumerated()), id: \.element.id) { index, segment in
                    SegmentRow(segment: segment, isHighlighted: index == highlightedIndex)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playback?.seekAndPlay(to: segment.start)
                        }
                    Divider()
                }
            }
        }
    }

    /// 現在の再生位置に対応するセグメントの index（ハイライト対象）。
    private var highlightedIndex: Int? {
        guard let playback else { return nil }
        let ranges = session.sortedSegments.map { SegmentTimeRange(start: $0.start, end: $0.end) }
        return AudioPlaybackController.segmentIndex(at: playback.currentTime, in: ranges)
    }
}

struct SegmentRow: View {
    let segment: SegmentModel
    var isHighlighted: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 話者カラーバー（Phase 3 で有効化）
            if let profile = segment.speakerProfile,
               let color = Color(hex: profile.colorHex) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4)
                    .padding(.vertical, 4)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 4)
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.speakerDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTimestamp(segment.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(segment.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal)
        .background(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

private extension Color {
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespaces)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6, let value = UInt64(str, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
