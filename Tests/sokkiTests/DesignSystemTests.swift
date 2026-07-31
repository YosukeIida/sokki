import Testing
import SwiftUI
@testable import SokkiKit

// MARK: - SpeakerLabel

@Suite("SpeakerLabel")
struct SpeakerLabelTests {

    private let ja = Locale(identifier: "ja_JP")
    private let en = Locale(identifier: "en_US")

    @Test("日本語ロケールは 話者A / 話者B 形式")
    func japanese() {
        #expect(SpeakerLabel.displayName(index: 0, locale: ja) == "話者A")
        #expect(SpeakerLabel.displayName(index: 1, locale: ja) == "話者B")
    }

    @Test("英語ロケールは Speaker A 形式")
    func english() {
        #expect(SpeakerLabel.displayName(index: 0, locale: en) == "Speaker A")
        #expect(SpeakerLabel.displayName(index: 1, locale: en) == "Speaker B")
    }

    @Test("index 25 は Z、26 は AA、27 は AB（桁上げ）")
    func letterRollover() {
        #expect(SpeakerLabel.displayName(index: 25, locale: en) == "Speaker Z")
        #expect(SpeakerLabel.displayName(index: 26, locale: en) == "Speaker AA")
        #expect(SpeakerLabel.displayName(index: 27, locale: en) == "Speaker AB")
    }

    @Test("桁上げは日本語でも同じ (話者AA)")
    func japaneseRollover() {
        #expect(SpeakerLabel.displayName(index: 26, locale: ja) == "話者AA")
    }

    @Test("負のインデックスは A にフォールバック")
    func negativeFallback() {
        #expect(SpeakerLabel.displayName(index: -1, locale: en) == "Speaker A")
    }
}

// MARK: - SokkiTokens.speakerColor

@Suite("SokkiTokens speakerColor")
struct SpeakerColorTests {

    @Test("3 色を巡回する (index と index+3 は同色)")
    func cyclesStably() {
        #expect(SokkiTokens.speakerColor(index: 0) == SokkiTokens.speakerColor(index: 3))
        #expect(SokkiTokens.speakerColor(index: 1) == SokkiTokens.speakerColor(index: 4))
        #expect(SokkiTokens.speakerColor(index: 2) == SokkiTokens.speakerColor(index: 5))
        #expect(SokkiTokens.speakerColor(index: 0) == SokkiTokens.speakerColor(index: 6))
    }

    @Test("パレット先頭 3 色は互いに異なる")
    func paletteDistinct() {
        let a = SokkiTokens.speakerColor(index: 0)
        let b = SokkiTokens.speakerColor(index: 1)
        let c = SokkiTokens.speakerColor(index: 2)
        #expect(a != b)
        #expect(b != c)
        #expect(a != c)
    }

    @Test("負のインデックスも安全に巡回する")
    func negativeWraps() {
        #expect(SokkiTokens.speakerColor(index: -1) == SokkiTokens.speakerColor(index: 2))
        #expect(SokkiTokens.speakerColor(index: -3) == SokkiTokens.speakerColor(index: 0))
    }
}

// MARK: - SokkiTokens テーマ

@Suite("SokkiTokens themes")
struct SokkiTokensThemeTests {

    @Test("manuscript と console は主要トークンが異なる値を持つ")
    func themesDiffer() {
        #expect(SokkiTokens.manuscript.accent != SokkiTokens.console.accent)
        #expect(SokkiTokens.manuscript.rec != SokkiTokens.console.rec)
        #expect(SokkiTokens.manuscript.text != SokkiTokens.console.text)
    }

    @Test("colorScheme からテーマを解決する (dark=console / light=manuscript)")
    func resolveByScheme() {
        #expect(SokkiTokens.resolve(for: .dark).accent == SokkiTokens.console.accent)
        #expect(SokkiTokens.resolve(for: .light).accent == SokkiTokens.manuscript.accent)
    }
}

// MARK: - SokkiAppearance

@Suite("SokkiAppearance")
struct SokkiAppearanceTests {

    @Test("preferredColorScheme のマッピング (system は nil)")
    func colorSchemeMapping() {
        #expect(SokkiAppearance.system.preferredColorScheme == nil)
        #expect(SokkiAppearance.light.preferredColorScheme == .light)
        #expect(SokkiAppearance.dark.preferredColorScheme == .dark)
    }
}

// MARK: - TimestampText

@Suite("TimestampText")
struct TimestampTextTests {

    @Test("mm:ss へ整形する")
    func formatsMMSS() {
        #expect(TimestampText.format(8) == "00:08")
        #expect(TimestampText.format(2703) == "45:03")
        #expect(TimestampText.format(65) == "01:05")
    }

    @Test("60 分以上でも分は連続表示")
    func formatsOverAnHour() {
        #expect(TimestampText.format(4500) == "75:00")
    }

    @Test("負値は 00:00 に丸める")
    func clampsNegative() {
        #expect(TimestampText.format(-5) == "00:00")
    }
}

// MARK: - Color(hex:)

@Suite("Color(hex:)")
struct ColorHexTests {

    @Test("# 付き 6 桁 hex をパースできる")
    func parsesWithHash() {
        #expect(Color(hex: "#3B82F6") == Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255))
    }

    @Test("# なしでもパースできる")
    func parsesWithoutHash() {
        #expect(Color(hex: "3B82F6") == Color(hex: "#3B82F6"))
    }

    @Test("6 桁以外・16 進数でない文字列は nil")
    func invalidReturnsNil() {
        #expect(Color(hex: "#FFF") == nil)
        #expect(Color(hex: "ZZZZZZ") == nil)
    }
}

// MARK: - SegmentRow.barColor

@Suite("SegmentRow barColor")
struct SegmentRowBarColorTests {

    @Test("同一 colorHex は同一色に解決される")
    func sameHexSameColor() {
        #expect(SegmentRow.barColor(colorHex: "#3B82F6") == SegmentRow.barColor(colorHex: "#3B82F6"))
    }

    @Test("colorHex が異なれば色も異なる")
    func differentHexDifferentColor() {
        #expect(SegmentRow.barColor(colorHex: "#3B82F6") != SegmentRow.barColor(colorHex: "#EF4444"))
    }

    @Test("プロファイル未割当（nil）はコントロールグレーにフォールバックする")
    func nilFallsBackToControlGray() {
        #expect(SegmentRow.barColor(colorHex: nil) == Color.secondary.opacity(0.3))
    }

    @Test("不正な hex もコントロールグレーにフォールバックする")
    func invalidHexFallsBackToControlGray() {
        #expect(SegmentRow.barColor(colorHex: "not-a-color") == Color.secondary.opacity(0.3))
    }
}
