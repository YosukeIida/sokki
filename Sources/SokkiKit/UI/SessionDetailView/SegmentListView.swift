import SwiftUI

struct SegmentListView: View {
    let session: SessionModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(session.sortedSegments) { segment in
                    SegmentRow(segment: segment)
                    Divider()
                }
            }
        }
    }
}

struct SegmentRow: View {
    let segment: SegmentModel

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
