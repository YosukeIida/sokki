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
