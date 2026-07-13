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
    @Environment(\.sokkiTokens) private var tokens
    var isHighlighted: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SpeakerColorBar(color: barColor)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    TimestampText(seconds: segment.start)
                        .font(.caption)
                    Text(segment.speakerDisplayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(tokens.muted)
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

    /// 話者カラーバーの色。同一 `speakerProfile` は同一色（`colorHex` 由来）になる。
    private var barColor: Color {
        Self.barColor(colorHex: segment.speakerProfile?.colorHex)
    }

    /// 話者プロファイルの `colorHex` からカラーバー色を解決する。
    /// SwiftData（`@Model`）非依存の純粋関数として切り出し、単体テスト可能にしている。
    /// - Parameter colorHex: `SpeakerProfileModel.colorHex`（例: "#3B82F6"）。
    ///   `nil`（プロファイル未割当）または不正な hex はコントロールグレーにフォールバックする。
    static func barColor(colorHex: String?) -> Color {
        guard let colorHex, let color = Color(hex: colorHex) else {
            return Color.secondary.opacity(0.3)
        }
        return color
    }
}
