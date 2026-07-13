#if canImport(AppKit)
import Testing
import AppKit
@testable import SokkiKit

@Suite("FloatingSubtitlePanel 属性")
@MainActor
struct FloatingSubtitlePanelTests {

    private func makePanel() -> FloatingSubtitlePanel {
        FloatingSubtitlePanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160))
    }

    @Test("sharingType = .none（画面共有に映り込まない）")
    func sharingTypeIsNone() {
        #expect(makePanel().sharingType == .none)
    }

    @Test("level = .floating（常に最前面）")
    func levelIsFloating() {
        #expect(makePanel().level == .floating)
    }

    @Test("styleMask に nonactivatingPanel を含む")
    func styleMaskIsNonactivating() {
        #expect(makePanel().styleMask.contains(.nonactivatingPanel))
    }

    @Test("styleMask に closable を含まない（ネイティブクローズボタンによる状態不整合を避ける）")
    func styleMaskExcludesClosable() {
        // .closable が有効だとネイティブの赤クローズボタンで直接閉じられてしまい、
        // FloatingSubtitleController.isVisible / RecordingView 側の表示状態と実際の
        // パネル状態がずれる。破棄は close() への一本化が契約なので .closable は含めない。
        #expect(makePanel().styleMask.contains(.closable) == false)
    }

    @Test("背景ドラッグ移動可・全 Space 表示・アプリ非アクティブ化")
    func overlayBehaviors() {
        let panel = makePanel()
        #expect(panel.isMovableByWindowBackground)
        #expect(panel.isFloatingPanel)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.canBecomeMain == false)
    }

    @Test("コントローラ: show/hide/toggle で isVisible が追従")
    func controllerVisibility() {
        let controller = FloatingSubtitleController(feed: SubtitleFeed())
        #expect(controller.isVisible == false)
        controller.show()
        #expect(controller.isVisible == true)
        controller.hide()
        #expect(controller.isVisible == false)
        controller.toggle()
        #expect(controller.isVisible == true)
        controller.close()
        #expect(controller.isVisible == false)
    }

    @Test("コントローラ: setClickThrough で ignoresMouseEvents が反映される")
    func controllerClickThrough() {
        let controller = FloatingSubtitleController(feed: SubtitleFeed())
        controller.show()
        controller.setClickThrough(true)
        #expect(controller.isClickThrough == true)
        controller.setClickThrough(false)
        #expect(controller.isClickThrough == false)
        controller.close()
    }
}
#endif
