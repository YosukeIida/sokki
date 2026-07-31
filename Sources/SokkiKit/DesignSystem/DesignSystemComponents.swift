import SwiftUI

/// mm:ss のタイムスタンプ表示。等幅数字（`.monospacedDigit()`）・faint 色。
/// 字幕／SRT 風の行頭タイムスタンプに用いる。出典: モックの `.seg-ts` / `.spk .ts`。
struct TimestampText: View {
    let seconds: Double
    @Environment(\.sokkiTokens) private var tokens

    var body: some View {
        Text(Self.format(seconds))
            .monospacedDigit()
            .foregroundStyle(tokens.faint)
    }

    /// 秒数を mm:ss へ整形する。60 分以上でも分は繰り上げず 2 桁以上で連続表示する（例: 75:00）。
    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 話者インジケータの縦カラーバー（幅 3・角丸）。出典: モックの `.seg-bar { width: 3px; border-radius: 2px }`。
/// 親の高さいっぱいに伸びる（呼び出し側が `frame`/レイアウトで縦幅を決める）。
struct SpeakerColorBar: View {
    let color: Color
    var width: CGFloat = SokkiTokens.barWidth   // = 3

    /// 話者色を直接指定して生成する。
    init(color: Color, width: CGFloat = SokkiTokens.barWidth) {
        self.color = color
        self.width = width
    }

    /// 話者インデックスからパレット色を解決して生成する。
    init(speakerIndex: Int, width: CGFloat = SokkiTokens.barWidth) {
        self.color = SokkiTokens.speakerColor(index: speakerIndex)
        self.width = width
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: width)
    }
}

// MARK: - Color(hex:)

extension Color {
    /// "#RRGGBB" / "RRGGBB" 形式の hex 文字列から Color を生成する。
    /// `SpeakerProfileModel.colorHex` など、声紋に紐づく永続化済みカラーの復元に用いる。
    /// パース失敗（6 桁以外・16 進数でない）時は `nil`。
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
