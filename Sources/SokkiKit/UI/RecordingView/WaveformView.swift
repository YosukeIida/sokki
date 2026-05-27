import SwiftUI

// Phase 2 で実装予定: リアルタイム波形・レベルメーター
struct WaveformView: View {
    let levelStream: AsyncStream<Float>
    let color: Color

    @State private var levels: [Float] = Array(repeating: -60, count: 80)
    @State private var currentLevel: Float = -60

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.7))
                        .frame(width: (geo.size.width / CGFloat(levels.count)) - 2,
                               height: barHeight(level: level, maxHeight: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .task {
            for await level in levelStream {
                await MainActor.run {
                    levels.removeFirst()
                    levels.append(level)
                    currentLevel = level
                }
            }
        }
    }

    private func barHeight(level: Float, maxHeight: CGFloat) -> CGFloat {
        let normalized = (level + 60) / 60   // -60…0 → 0…1
        return max(2, CGFloat(normalized) * maxHeight)
    }
}

struct LevelMeterView: View {
    let label: String
    let level: Float   // dBFS, -60…0
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(height: geo.size.height * CGFloat((level + 60) / 60))
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
