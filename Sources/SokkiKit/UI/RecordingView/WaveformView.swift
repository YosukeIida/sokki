import SwiftUI

/// dBFS（-60...0）を表示正規化（0...1）へ写像する純粋関数。
/// WaveformView / LevelMeterView の高さ計算を一本化し、mic / system 双方の見た目の一貫性を保つ（TASK-13）。
enum LevelMeterMath {
    static func normalize(dBFS level: Float) -> CGFloat {
        let normalized = (level + 60) / 60
        return CGFloat(max(0, min(1, normalized)))
    }
}

// mic=青 / system=赤の実レベルを表示するリアルタイム波形・レベルメーター（TASK-13）
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
        max(2, LevelMeterMath.normalize(dBFS: level) * maxHeight)
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
                        .frame(height: geo.size.height * LevelMeterMath.normalize(dBFS: level))
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
