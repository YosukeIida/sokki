import SwiftUI

struct SessionRowView: View {
    let session: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(session.createdAt, style: .date)
                Text(session.createdAt, style: .time)
                if session.durationSeconds > 0 {
                    Text("·")
                    Text(formatDuration(session.durationSeconds))
                        .accessibilityIdentifier("sessionRow.duration")
                }
                Text("·")
                Text("\(session.segments.count) セグメント")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
