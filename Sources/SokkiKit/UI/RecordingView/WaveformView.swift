import SwiftUI

/// dBFS（-60...0）を表示正規化（0...1）へ写像する純粋関数。
/// WaveformView / LevelMeterView の高さ計算を一本化し、mic / system 双方の見た目の一貫性を保つ（TASK-13）。
enum LevelMeterMath {
    static func normalize(dBFS level: Float) -> CGFloat {
        let normalized = (level + 60) / 60
        return CGFloat(max(0, min(1, normalized)))
    }

    /// 表示更新のスロットリング判定（純粋関数）。
    /// system 側の IO コールバック（Core Audio Taps）はデバイスのネイティブバッファ長で駆動され、
    /// mic 側より高頻度になりうる。値が来るたびに MainActor へホップして配列更新・再描画するのは
    /// 表示上不要な負荷になるため、最小更新間隔で間引く（codex レビュー対応・TASK-13）。
    /// ウォールクロック（`Date`）は後退しうる（NTP補正・手動時刻変更）ため、単調クロックの
    /// 経過時間（`Duration`、`ContinuousClock` 由来）で判定する（codex 再レビュー対応）。
    static func shouldUpdate(elapsed: Duration, minInterval: Duration) -> Bool {
        elapsed >= minInterval
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
            // system レーンは mic より高頻度になりうるため、表示更新は最大 ~30fps に間引く
            // （音声認識・録音側の配送には一切影響しない。UI 消費側のみのスロットリング）。
            // ContinuousClock は単調クロックのため、ウォールクロック調整の影響を受けない。
            let clock = ContinuousClock()
            var lastUpdate = clock.now
            let minUpdateInterval: Duration = .milliseconds(33)
            for await level in levelStream {
                let now = clock.now
                guard LevelMeterMath.shouldUpdate(elapsed: lastUpdate.duration(to: now), minInterval: minUpdateInterval) else {
                    continue
                }
                lastUpdate = now
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
