import AppKit
import XCTest

/// backlog TASK-6 (P1-3 / GitHub #25) / TASK-7 (P1-4 / GitHub #26) の実機 E2E 確認を
/// XCUITest として自動化したもの。実際の sokki.app を起動し、マイク録音→文字起こし→
/// 一覧・詳細表示→エクスポートまでの一気通貫フローを検証する。
///
/// 前提: マイクのアクセス許可が事前に付与されていること（初回はダイアログが出るため
/// このテストでは自動許可できない。手動で一度許可しておくこと）。
///
/// production データからの隔離: テストごとに一時ディレクトリを発行し、
/// `SOKKI_UITEST_STORE_URL` / `SOKKI_UITEST_RECORDINGS_DIR` 経由でアプリに
/// 専用の SwiftData ストアと録音保存先を使わせる（`sokki` 通常 scheme の実行や
/// 利用者本人の録音データに影響しない）。この scheme は project.yml の `sokkiE2E`
/// でのみビルドされ、通常の `sokki` scheme には含まれない。
@MainActor
final class SokkiUITests: XCTestCase {
    private var app: XCUIApplication!
    private var tempRootDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        tempRootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sokkiE2E_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRootDirectory, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchEnvironment["SOKKI_UITEST_STORE_URL"] =
            tempRootDirectory.appendingPathComponent("sokkiE2E.store.sqlite").path
        app.launchEnvironment["SOKKI_UITEST_RECORDINGS_DIR"] =
            tempRootDirectory.appendingPathComponent("recordings", isDirectory: true).path
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: tempRootDirectory)
    }

    private var recordingsDirectory: URL {
        tempRootDirectory.appendingPathComponent("recordings", isDirectory: true)
    }

    /// マイク録音を開始し、モデル準備完了を待ってから数秒録音して停止する。
    /// 一覧画面に移動し、作成されたセッションの先頭行を返す。
    @discardableResult
    private func recordShortSessionAndReturnToList() throws -> XCUIElement {
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
        return firstRow
    }

    /// TASK-6: マイク録音→停止→録音一覧に反映されることを確認する。
    /// 先頭行の存在だけでなく、録音ファイルの実体・duration・タイトルが実際に
    /// 保存されていること、およびエクスポート結果がこのセッション由来であることまで確認する。
    func testRecordStopAndAppearsInSessionList() throws {
        let firstRow = try recordShortSessionAndReturnToList()

        // 録音ファイルが実際にディスクへ書き出されていること（P1-1 経路）を確認する。
        let recordingFiles: [URL]
        do {
            recordingFiles = try FileManager.default.contentsOfDirectory(
                at: recordingsDirectory, includingPropertiesForKeys: [.fileSizeKey]
            )
        } catch {
            XCTFail("録音ディレクトリの読み取りに失敗（録音ファイルが保存されていない可能性）: \(error)")
            return
        }
        XCTAssertEqual(recordingFiles.count, 1, "録音ファイルが1つ生成されているはず")
        if let recordingFile = recordingFiles.first {
            let fileSize = try recordingFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertGreaterThan(fileSize, 0, "録音ファイルのサイズが0（音声が書き込まれていない）")
        }

        // セッションタイトル（自動生成される "録音_yyyyMMdd_HHmm" 形式）が一覧行に表示されていること。
        let titlePredicate = NSPredicate(format: "label BEGINSWITH %@", "録音_")
        let titleText = firstRow.staticTexts.matching(titlePredicate).firstMatch
        XCTAssertTrue(titleText.waitForExistence(timeout: 5), "セッションタイトルが見つからない")
        let sessionTitle = titleText.label

        // duration（"m:ss" 形式）が保存され表示されていること。
        // 作成日時（createdAt の time スタイル）も同じ "[0-9]+:[0-9]{2}" パターンに
        // マッチし得る（24時間表記ロケールなど）ため、accessibilityIdentifier で明示的に特定する。
        let durationText = firstRow.descendants(matching: .any)["sessionRow.duration"]
        XCTAssertTrue(
            durationText.waitForExistence(timeout: 5),
            "録音時間の表示が見つからない（duration が保存されていない可能性）"
        )
        let durationPredicate = NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")
        XCTAssertTrue(
            durationPredicate.evaluate(with: durationText.label),
            "duration の表示形式が想定と異なる: \(durationText.label)"
        )

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
        // MarkdownExporter は先頭行に "## <タイトル>" を出力する（Sources/SokkiKit/Export/MarkdownExporter.swift）。
        // タイトルの一致まで見ることで、別セッションの内容が混入していないことを保証する。
        XCTAssertTrue(
            pasteboardText?.contains("## \(sessionTitle)") ?? false,
            "クリップボードの内容がこのセッションの Markdown になっていない"
        )
    }

    /// TASK-7: 「ファイルへ保存…」で保存ダイアログが開くことを確認する。
    /// 一時ストアに隔離されているため、このテスト自身で録音してセッションを用意する
    /// （他テストの実行順序や既存データに依存しない）。
    func testExportSaveDialogAppears() throws {
        let firstRow = try recordShortSessionAndReturnToList()
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
