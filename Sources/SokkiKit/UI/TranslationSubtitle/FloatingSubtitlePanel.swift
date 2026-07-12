#if canImport(AppKit)
import AppKit
import SwiftUI

/// 会議横に常駐させるフローティング字幕オーバーレイのパネル。
///
/// 受け入れ基準 #2 の要求を満たす AppKit 属性を集約する:
/// - `sharingType = .none`: **画面共有・画面収録に映り込まない**（最重要）。
/// - `level = .floating` + `isFloatingPanel`: 常に最前面。
/// - `.nonactivatingPanel`: 前面化してもアプリをアクティブ化せず、背後の会議アプリの
///   フォーカスを奪わない。
/// - `collectionBehavior`: 全 Space・フルスクリーンの会議アプリ上にも表示。
/// - `isMovableByWindowBackground`: 背景ドラッグで移動可能。
///
/// クリック透過（`ignoresMouseEvents`）は `FloatingSubtitleController` が切り替える。
@MainActor
final class FloatingSubtitlePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // --- 映り込み防止（受け入れ基準 #2）---
        sharingType = .none

        // --- 最前面・フローティング ---
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // --- ドラッグ移動 ---
        isMovableByWindowBackground = true

        // --- オーバーレイ外観（半透明・chrome 最小化）---
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    // nonactivating でもドラッグ・クローズ操作のため key にはなれる。main にはならない
    // （背後の会議アプリのメインウィンドウ性を奪わない）。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// フローティング字幕パネルのライフサイクル所有者。
///
/// パネル生成・表示/非表示・クリック透過・破棄を一元管理する。SwiftUI の `@State` として
/// ビューが保持し、翻訳有効時の表示トグルと、録音停止・ビュー破棄時の `close()` を呼ぶ。
///
/// `@Observable` な `feed` / `coordinator` を `NSHostingView` のルート
/// (`SubtitleLanesContainer`) が直接読むため、データ更新は SwiftUI 側で自動反映される
/// （コントローラは配管のみ・毎フレーム push しない）。
@MainActor
final class FloatingSubtitleController {
    private let feed: SubtitleFeed
    private var coordinator: TranslationCoordinator?
    private var tokens: SokkiTokens

    private var panel: FloatingSubtitlePanel?

    private(set) var isVisible = false
    private(set) var isClickThrough = false

    init(
        feed: SubtitleFeed,
        coordinator: TranslationCoordinator? = nil,
        tokens: SokkiTokens = .console
    ) {
        self.feed = feed
        self.coordinator = coordinator
        self.tokens = tokens
    }

    /// パネルを生成（未生成なら）して最前面に表示する。
    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.ignoresMouseEvents = isClickThrough
        // nonactivating: アプリをアクティブ化せず最前面へ。
        panel.orderFrontRegardless()
        isVisible = true
    }

    /// パネルを隠す（インスタンスは保持し、再表示で再利用する）。
    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// クリック透過の切り替え。ON のときマウスイベントを背後へ通す（ドラッグ移動は不可になる）。
    func setClickThrough(_ enabled: Bool) {
        isClickThrough = enabled
        panel?.ignoresMouseEvents = enabled
    }

    /// 表示テーマを差し替える（外観設定変更時）。ルートビューの environment を作り直す。
    func updateTokens(_ tokens: SokkiTokens) {
        self.tokens = tokens
        if let panel { panel.contentView = makeHostingView() }
    }

    /// 上流マージ後に翻訳 Coordinator を注入する結線点。以後、訳文レーンが有効化する。
    func attach(coordinator: TranslationCoordinator?) {
        self.coordinator = coordinator
        if let panel { panel.contentView = makeHostingView() }
    }

    /// パネルを破棄する。録音停止・ビュー破棄・アプリ終了で所有者が明示的に呼ぶ
    /// （`@MainActor` クラスは deinit から AppKit 破棄を安全に走らせられないため）。
    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        isVisible = false
    }

    // MARK: - Private

    private func makePanel() -> FloatingSubtitlePanel {
        let size = NSSize(width: 520, height: 200)
        let panel = FloatingSubtitlePanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = makeHostingView()

        // 初期位置: メイン画面の右下寄り。
        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - 24,
                y: visible.minY + 24
            ))
        }
        return panel
    }

    private func makeHostingView() -> NSHostingView<AnyView> {
        let root = SubtitleLanesContainer(feed: feed, coordinator: coordinator)
            .environment(\.sokkiTokens, tokens)
            .background(.ultraThinMaterial)   // 半透明オーバーレイ背景。
        return NSHostingView(rootView: AnyView(root))
    }
}
#endif
