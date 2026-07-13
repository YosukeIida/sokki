import Foundation
import Testing
@testable import SokkiKit

// MARK: - LevelMeterMath（TASK-13: dBFS → 表示正規化の純粋関数）

@Suite("LevelMeterMath")
struct LevelMeterMathTests {

    @Test("下限 -60dBFS は 0 へ写像される")
    func floorMapsToZero() {
        #expect(LevelMeterMath.normalize(dBFS: -60) == 0)
    }

    @Test("上限 0dBFS は 1 へ写像される")
    func ceilingMapsToOne() {
        #expect(LevelMeterMath.normalize(dBFS: 0) == 1)
    }

    @Test("中間値 -30dBFS は 0.5 へ写像される")
    func midpointMapsToHalf() {
        #expect(LevelMeterMath.normalize(dBFS: -30) == 0.5)
    }

    @Test("範囲外（下）はクランプされる")
    func clampsBelowFloor() {
        #expect(LevelMeterMath.normalize(dBFS: -120) == 0)
    }

    @Test("範囲外（上）はクランプされる")
    func clampsAboveCeiling() {
        #expect(LevelMeterMath.normalize(dBFS: 10) == 1)
    }

    @Test("mic / system は同一の写像関数を通る（見た目の一貫性を固定）")
    func micAndSystemShareSameMapping() {
        let level: Float = -18
        #expect(LevelMeterMath.normalize(dBFS: level) == LevelMeterMath.normalize(dBFS: level))
    }

    // MARK: - shouldUpdate（表示更新のスロットリング判定・codex レビュー対応 TASK-13）

    @Test("最小間隔未満の経過では更新しない")
    func shouldUpdateRejectsWithinMinInterval() {
        let last = Date(timeIntervalSinceReferenceDate: 0)
        let now = last.addingTimeInterval(0.01)
        #expect(LevelMeterMath.shouldUpdate(now: now, lastUpdate: last, minInterval: 1.0 / 30) == false)
    }

    @Test("最小間隔ちょうど、またはそれ以上の経過では更新する")
    func shouldUpdateAllowsAtOrAfterMinInterval() {
        let last = Date(timeIntervalSinceReferenceDate: 0)
        let exact = last.addingTimeInterval(1.0 / 30)
        let later = last.addingTimeInterval(1.0)
        #expect(LevelMeterMath.shouldUpdate(now: exact, lastUpdate: last, minInterval: 1.0 / 30) == true)
        #expect(LevelMeterMath.shouldUpdate(now: later, lastUpdate: last, minInterval: 1.0 / 30) == true)
    }
}
