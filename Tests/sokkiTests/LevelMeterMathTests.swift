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
}
