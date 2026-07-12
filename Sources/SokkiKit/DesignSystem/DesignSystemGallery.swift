import SwiftUI

/// デザインシステムの一覧（ギャラリー）ビュー。
/// 全カラートークンのスウォッチ・話者パレット・`TimestampText`・`SpeakerColorBar` を並べて
/// テーマ（Manuscript / Console）の見え方を目視確認するための開発補助ビュー。
///
/// テーマは environment の `\.sokkiTokens` から解決するため、プレビュー側で
/// `.environment(\.sokkiTokens, .manuscript / .console)` と `.preferredColorScheme(_:)` を
/// 合わせて指定する。
struct DesignSystemGallery: View {
    @Environment(\.sokkiTokens) private var tokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("sokki デザインシステム")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tokens.text)

                swatchGroup("面 (surface)", [
                    ("contentBg", tokens.contentBg),
                    ("titlebar", tokens.titlebar),
                    ("sidebar", tokens.sidebar),
                    ("transcriptBg", tokens.transcriptBg),
                    ("controlsBg", tokens.controlsBg),
                    ("segBg", tokens.segBg),
                ])

                swatchGroup("罫線・テキスト", [
                    ("line", tokens.line),
                    ("text", tokens.text),
                    ("muted", tokens.muted),
                    ("faint", tokens.faint),
                ])

                swatchGroup("アクセント・状態", [
                    ("accent", tokens.accent),
                    ("accentOn", tokens.accentOn),
                    ("good", tokens.good),
                    ("rec", tokens.rec),
                ])

                swatchGroup("波形ソース・翻訳", [
                    ("mic", tokens.mic),
                    ("sys", tokens.sys),
                    ("transRail", tokens.transRail),
                ])

                speakerSection
                componentSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.contentBg)
    }

    // MARK: - 話者パレット

    private var speakerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("話者パレット (テーマ共通)")
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    swatch(SpeakerLabel.displayName(index: i, locale: Locale(identifier: "en")),
                           SokkiTokens.speakerColor(index: i))
                }
            }
        }
    }

    // MARK: - コンポーネント

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("コンポーネント")
            HStack(alignment: .center, spacing: 16) {
                // TimestampText
                VStack(alignment: .leading, spacing: 4) {
                    TimestampText(seconds: 8)
                    TimestampText(seconds: 2703)   // 45:03
                }
                // SpeakerColorBar × 3 話者
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 6) {
                            SpeakerColorBar(speakerIndex: i)
                                .frame(height: 36)
                            Text(SpeakerLabel.displayName(index: i))
                                .font(.caption)
                                .foregroundStyle(tokens.muted)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 部品

    private func swatchGroup(_ title: String, _ items: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                      alignment: .leading, spacing: 12) {
                ForEach(items, id: \.0) { name, color in
                    swatch(name, color)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tokens.muted)
            .textCase(.uppercase)
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(tokens.line, lineWidth: 1)
                )
            Text(name)
                .font(.caption2)
                .foregroundStyle(tokens.faint)
        }
    }
}

#if DEBUG
#Preview("Manuscript (Light)") {
    DesignSystemGallery()
        .environment(\.sokkiTokens, .manuscript)
        .preferredColorScheme(.light)
        .frame(width: 520, height: 720)
}

#Preview("Console (Dark)") {
    DesignSystemGallery()
        .environment(\.sokkiTokens, .console)
        .preferredColorScheme(.dark)
        .frame(width: 520, height: 720)
}
#endif
