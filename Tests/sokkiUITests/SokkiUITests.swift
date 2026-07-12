import AppKit
import XCTest

/// backlog TASK-6 (P1-3 / GitHub #25) / TASK-7 (P1-4 / GitHub #26) の実機 E2E 確認を
/// XCUITest として自動化したもの。実際の sokki.app を起動し、マイク録音→文字起こし→
/// 一覧・詳細表示→エクスポートまでの一気通貫フローを検証する。
///
/// 前提: マイクのアクセス許可が事前に付与されていること（初回はダイアログが出るため
/// このテストでは自動許可できない。手動で一度許可しておくこと）。
@MainActor
final class SokkiUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// TASK-6: マイク録音→停止→録音一覧に反映されることを確認する。
    func testRecordStopAndAppearsInSessionList() throws {
        let recordButton = app.descendants(matching: .any)["recordStopButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "録音ボタンが見つからない")

        recordButton.click()

        // モデル準備（ダウンロード済みなら数秒、初回はダウンロードに数分）を待ってから
        // 録音状態（経過時間表示）になるのを確認する。
        // 経過時間の Text は accessibility 上 label ではなく value に入るため両方を見る。
        let elapsedPredicate = NSPredicate(
            format: "label MATCHES %@ OR value MATCHES %@",
            "[0-9]{2}:[0-9]{2}", "[0-9]{2}:[0-9]{2}"
        )
        let elapsedText = app.staticTexts.matching(elapsedPredicate).firstMatch
        XCTAssertTrue(
            elapsedText.waitForExistence(timeout: 120),
            "録音が開始されない（モデル準備に失敗した可能性）"
        )

        // 数秒録音してから停止する
        Thread.sleep(forTimeInterval: 3)
        recordButton.click()

        // 停止処理（フラッシュ）の完了を待つ: 経過時間表示が消えるまで
        let notRunning = NSPredicate(format: "exists == false")
        expectation(for: notRunning, evaluatedWith: elapsedText, handler: nil)
        waitForExpectations(timeout: 30)

        // 録音一覧に移動し、セッションが追加されていることを確認する
        let sessionListNav = app.descendants(matching: .any)["sidebar.sessionList"]
        XCTAssertTrue(sessionListNav.waitForExistence(timeout: 5))
        sessionListNav.click()

        let firstRow = app.descendants(matching: .any).matching(identifier: "sessionRow").firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "録音一覧にセッションが表示されない")

        // TASK-7: 詳細画面でエクスポート（Markdownコピー）を確認する
        firstRow.click()

        // SwiftUI の Menu + "square.and.arrow.up" はツールバー上で macOS 標準の
        // 共有ボタン（accessibility title は表示ラベル "エクスポート" ではなく "Share"、
        // 型は MenuButton）として扱われるため、identifier で広く検索する。
        let exportButton = app.descendants(matching: .any)["square.and.arrow.up"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "エクスポートボタンが見つからない")
        exportButton.click()

        let copyMarkdown = app.menuItems["Markdown としてコピー"]
        XCTAssertTrue(
            copyMarkdown.waitForExistence(timeout: 5),
            "「Markdown としてコピー」メニュー項目が見つからない"
        )
        copyMarkdown.click()

        let pasteboardText = NSPasteboard.general.string(forType: .string)
        XCTAssertNotNil(pasteboardText, "クリップボードに内容がコピーされていない")
        XCTAssertFalse(pasteboardText?.isEmpty ?? true, "クリップボードの内容が空")
    }

    /// TASK-7: 「ファイルへ保存…」で保存ダイアログが開くことを確認する。
    /// 既存セッション（前のテストや手動操作で作成済み）が一覧にある前提。無ければスキップする。
    func testExportSaveDialogAppears() throws {
        let sessionListNav = app.descendants(matching: .any)["sidebar.sessionList"]
        XCTAssertTrue(sessionListNav.waitForExistence(timeout: 5))
        sessionListNav.click()

        let firstRow = app.descendants(matching: .any).matching(identifier: "sessionRow").firstMatch
        guard firstRow.waitForExistence(timeout: 5) else {
            throw XCTSkip("録音セッションが1件も無いためスキップ（先に testRecordStopAndAppearsInSessionList を実行してください）")
        }
        firstRow.click()

        let exportButton = app.descendants(matching: .any)["square.and.arrow.up"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.click()

        let saveMenuItem = app.menuItems["ファイルへ保存…"]
        XCTAssertTrue(saveMenuItem.waitForExistence(timeout: 5))
        saveMenuItem.click()

        // ExportSaveService は親ウィンドウなしで NSSavePanel.begin() を呼ぶため、
        // シート/ダイアログではなく identifier "save-panel" を持つ独立ウィンドウとして現れる。
        let savePanel = app.windows["save-panel"]
        XCTAssertTrue(savePanel.waitForExistence(timeout: 5), "保存ダイアログが表示されない")

        // 保存はせずダイアログを閉じる
        app.typeKey(.escape, modifierFlags: [])
    }
}
