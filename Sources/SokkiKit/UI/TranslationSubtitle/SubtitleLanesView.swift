import SwiftUI

/// 原文 / 訳文の 2 レーン表示（純プレゼンテーション）。
///
/// アプリ内ビューにもフローティングパネル (`FloatingSubtitlePanel`) にも同じ見た目で載せる
/// ため、状態を持たず表示値 (`[SubtitleLine]`) とバナー状態だけを受け取る。組み立て
/// （原文列 × 訳文辞書 → `[SubtitleLine]`）は `SubtitleFeed.makeLines` が担う。
///
/// 色は `\.sokkiTokens`（Console/Manuscript 両テーマ）に準拠。原文は主テキスト色、訳文は
/// 翻訳レール色 (`transRail`) のアクセントを左に添えて `muted` 寄りに落とす。
struct SubtitleLanesView: View {
    let lines: [SubtitleLine]
    /// プライバシー透明性バナー（クラウド送信中／DL 必要 等）。`nil` なら非表示。
    var statusBanner: String?
    /// クラウド送信中か（バナーのアイコン切り替え）。
    var isCloudActive: Bool
    /// 空表示時のプレースホルダ（フローティング時の視認性・待機表示用）。
    var placeholder: String

    @Environment(\.sokkiTokens) private var tokens

    init(
        lines: [SubtitleLine],
        statusBanner: String? = nil,
        isCloudActive: Bool = false,
        placeholder: String = "翻訳字幕（待機中）"
    ) {
        self.lines = lines
        self.statusBanner = statusBanner
        self.isCloudActive = isCloudActive
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let banner = statusBanner {
                bannerView(banner)
            }

            if lines.isEmpty {
                placeholderView
            } else {
                linesView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Lines

    private var linesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        lineRow(line).id(line.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: lines.last?.id) {
                if let last = lines.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func lineRow(_ line: SubtitleLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // 翻訳あり行の左レール（デザインモック --trans-rail 準拠）。
            Rectangle()
                .fill(line.translated != nil ? tokens.transRail : Color.clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 3) {
                // 原文レーン（即時）。
                Text(line.original)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tokens.text)
                    .textSelection(.enabled)

                // 訳文レーン（遅延到着）。
                if let translated = line.translated {
                    Text(translated)
                        .font(.system(size: 14))
                        .foregroundStyle(tokens.muted)
                        .textSelection(.enabled)
                } else {
                    // 翻訳待ち。
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("翻訳中…")
                            .font(.system(size: 12))
                            .foregroundStyle(tokens.faint)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Banner / placeholder

    private func bannerView(_ text: String) -> some View {
        Label(text, systemImage: isCloudActive ? "cloud" : "info.circle")
            .font(.system(size: 12))
            .foregroundStyle(isCloudActive ? tokens.accent : tokens.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.segBg)
    }

    private var placeholderView: some View {
        Text(placeholder)
            .font(.system(size: 13))
            .foregroundStyle(tokens.faint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
    }
}

/// `SubtitleFeed`（原文）と `TranslationCoordinator`（訳文）を観測して `SubtitleLanesView` を
/// 描画するコンテナ。フローティングパネルの `NSHostingView` ルート、アプリ内 2 レーン表示の
/// 両方で使う。
///
/// `@Observable` な `feed` / `coordinator` を body 内で読むため、原文列・訳文辞書・バナーの
/// いずれの変化でも再描画される。`coordinator` は上流（TASK-14 系列）マージ後に注入する想定で、
/// 本ブランチでは `nil`（原文レーンのみ・訳文は「翻訳中…」表示）でも成立する。
struct SubtitleLanesContainer: View {
    let feed: SubtitleFeed
    var coordinator: TranslationCoordinator?

    var body: some View {
        SubtitleLanesView(
            lines: feed.makeLines(translations: coordinator?.translations ?? [:]),
            statusBanner: coordinator?.statusBanner,
            isCloudActive: coordinator?.isCloudActive ?? false
        )
    }
}

#if DEBUG
private func sampleLines() -> [SubtitleLine] {
    [
        SubtitleLine(id: UUID(), original: "本日はお集まりいただきありがとうございます。",
                     translated: "Thank you all for gathering here today.", sourceTime: 0),
        SubtitleLine(id: UUID(), original: "まず先週の進捗から共有します。",
                     translated: "First, let me share last week's progress.", sourceTime: 1),
        SubtitleLine(id: UUID(), original: "次のリリースは来月を予定しています。",
                     translated: nil, sourceTime: 2),
    ]
}

#Preview("2レーン Console（ダーク）") {
    SubtitleLanesView(lines: sampleLines(), statusBanner: "Apple 翻訳（オンデバイス）")
        .environment(\.sokkiTokens, .console)
        .frame(width: 520, height: 240)
        .background(SokkiTokens.console.transcriptBg)
}

#Preview("2レーン Manuscript（ライト）") {
    SubtitleLanesView(lines: sampleLines(), statusBanner: "deepL で翻訳中（クラウド送信）", isCloudActive: true)
        .environment(\.sokkiTokens, .manuscript)
        .frame(width: 520, height: 240)
        .background(SokkiTokens.manuscript.transcriptBg)
}

#Preview("空（待機中）") {
    SubtitleLanesView(lines: [])
        .environment(\.sokkiTokens, .console)
        .frame(width: 520, height: 160)
        .background(SokkiTokens.console.transcriptBg)
}
#endif
