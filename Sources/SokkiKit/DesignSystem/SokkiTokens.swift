import SwiftUI

/// セマンティックカラートークン。
///
/// 値の正（source of truth）は確定済みデザインモックの CSS カスタムプロパティ:
/// - `docs/design/recording-view-v2.html` の `.dir-console` / `.dir-manuscript`
/// - `docs/design/session-list-v1.html` / `session-detail-v1.html`（同一値）
///
/// 各 hex はモック CSS からそのまま転記している（末尾コメントに CSS 変数名を併記）。
/// トークンの意味は「面（surface）／罫線・テキスト／アクセント・状態／波形ソース／翻訳レール」
/// の順にグループ化してある。
struct SokkiTokens {
    // 面（surface）
    let contentBg: Color        // --content-bg
    let titlebar: Color         // --titlebar
    let sidebar: Color          // --sidebar
    let transcriptBg: Color     // --transcript-bg
    let controlsBg: Color       // --controls-bg
    let segBg: Color            // --seg-bg

    // 罫線・テキスト
    let line: Color             // --line
    let text: Color             // --text
    let muted: Color            // --muted
    let faint: Color            // --faint

    // アクセント・状態
    let accent: Color           // --accent
    let accentOn: Color         // --accent-on（accent 上に載る前景色）
    let good: Color             // --good
    let rec: Color              // --rec（録音インジケータ）

    // 波形ソース
    let mic: Color              // --mic
    let sys: Color              // --sys

    // 翻訳
    let transRail: Color        // --trans-rail（翻訳あり行の左レール）
}

// MARK: - テーマ別トークン

extension SokkiTokens {
    /// Console（ダーク）: 鎮めた計器・ティール1点・同軸波形。
    /// 出典: `docs/design/recording-view-v2.html` の `.dir-console`
    static let console = SokkiTokens(
        contentBg: Color(hex6: 0x1a1e24),
        titlebar: Color(hex6: 0x1e232a),
        sidebar: Color(hex6: 0x171b20),
        transcriptBg: Color(hex6: 0x16191e),
        controlsBg: Color(hex6: 0x171b20),
        segBg: Color(hex6: 0x13161b),
        line: Color(hex6: 0x2a2f37),
        text: Color(hex6: 0xe3e6eb),
        muted: Color(hex6: 0x939ba7),
        faint: Color(hex6: 0x626a76),
        accent: Color(hex6: 0x35a597),
        accentOn: Color(hex6: 0x042420),
        good: Color(hex6: 0x4fb48f),
        rec: Color(hex6: 0xd9534c),
        mic: Color(hex6: 0x6e96c9),
        sys: Color(hex6: 0xc27c6e),
        transRail: Color(hex6: 0x2e7e74)
    )

    /// Manuscript（ライト）: 冷たい紙・墨・朱、読み幅で文書感。
    /// 出典: `docs/design/recording-view-v2.html` の `.dir-manuscript`
    static let manuscript = SokkiTokens(
        contentBg: Color(hex6: 0xfafaf8),
        titlebar: Color(hex6: 0xeeefec),
        sidebar: Color(hex6: 0xf1f2f0),
        transcriptBg: Color(hex6: 0xfbfbf9),
        controlsBg: Color(hex6: 0xf1f2f0),
        segBg: Color(hex6: 0xe9eae6),
        line: Color(hex6: 0xe1e3df),
        text: Color(hex6: 0x21242b),
        muted: Color(hex6: 0x5e6571),
        faint: Color(hex6: 0x9aa0a6),
        accent: Color(hex6: 0x2b4a78),
        accentOn: Color(hex6: 0xffffff),
        good: Color(hex6: 0x3c7a50),
        rec: Color(hex6: 0xc23b2c),
        mic: Color(hex6: 0x486593),
        sys: Color(hex6: 0xa06b50),
        transRail: Color(hex6: 0xc8d0dc)
    )
}

// MARK: - 話者パレット（テーマ共通）

extension SokkiTokens {
    /// 話者色はライト・ダーク共通（声紋に紐づく固定色）。
    /// 出典: 各モックの `--spk-a` / `--spk-b` / `--spk-c`。
    static let speakerA = Color(hex6: 0x4c7fc0)   // --spk-a（青）
    static let speakerB = Color(hex6: 0x3e9d6a)   // --spk-b（緑）
    static let speakerC = Color(hex6: 0x7c5cff)   // --spk-c（紫）

    /// 話者色の巡回パレット（A→B→C）。
    static let speakerPalette: [Color] = [speakerA, speakerB, speakerC]

    /// 話者インデックス（0始まり）を 3 色パレットに巡回で割り当てる。
    /// 4 話者以上は先頭に戻って再利用する（4 人以上のスケーリングはデザイン上のオープン
    /// クエスチョンのため、暫定で単純巡回とする）。負値も安全に巡回へ丸める。
    static func speakerColor(index: Int) -> Color {
        let count = speakerPalette.count
        let wrapped = ((index % count) + count) % count
        return speakerPalette[wrapped]
    }
}

// MARK: - 波形定数

extension SokkiTokens {
    /// 波形バーの幅（Voice Memos 風・対称棒）。出典: モック `.wave-vm i { width: 3px }`。
    static let barWidth: CGFloat = 3
    /// 波形バー間の隙間。出典: モック `.wave-vm { gap: 4px }`。
    static let barGap: CGFloat = 4
}

// MARK: - 内部ヘルパー

private extension Color {
    /// 6 桁 hex（0xRRGGBB）から sRGB Color を生成する。
    /// モック CSS の hex 値をそのまま `0x...` リテラルで移植し、目視照合できるようにするための内部ヘルパー。
    init(hex6 value: UInt32) {
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Environment 注入

private struct SokkiTokensKey: EnvironmentKey {
    /// 既定は Manuscript（ライト）。
    static let defaultValue: SokkiTokens = .manuscript
}

extension EnvironmentValues {
    /// 現在の実効テーマのセマンティックカラートークン。
    /// ルートで `sokkiDesignSystem()` を適用すると外観設定に応じて解決される。
    var sokkiTokens: SokkiTokens {
        get { self[SokkiTokensKey.self] }
        set { self[SokkiTokensKey.self] = newValue }
    }
}
