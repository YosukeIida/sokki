import Testing
import Foundation
@testable import SokkiKit

// MARK: - Helpers

/// テストごとに独立した UserDefaults を用意する（他テストとキーが衝突しないよう suiteName を都度発行）。
private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "sokkiTest.exportBookmark.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeTmpDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sokkiTest_exportDir_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// MARK: - ExportDirectoryBookmarkStore Tests

@Suite("ExportDirectoryBookmarkStore")
struct ExportDirectoryBookmarkStoreTests {

    @Test("保存→復元のラウンドトリップで同じディレクトリが得られる")
    func roundTrip() throws {
        let defaults = makeIsolatedDefaults()
        let store = ExportDirectoryBookmarkStore(defaults: defaults, key: "test.bookmark")
        let dir = makeTmpDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.save(directoryURL: dir)
        let restored = store.restoreDirectoryURL()

        #expect(restored?.standardizedFileURL.path == dir.standardizedFileURL.path)
    }

    @Test("未保存時は nil を返す")
    func nilWhenNotSaved() {
        let defaults = makeIsolatedDefaults()
        let store = ExportDirectoryBookmarkStore(defaults: defaults, key: "test.bookmark")

        #expect(store.restoreDirectoryURL() == nil)
    }

    @Test("壊れた Data が保存されている場合は nil を返す")
    func nilWhenDataIsCorrupt() {
        let defaults = makeIsolatedDefaults()
        let key = "test.bookmark"
        defaults.set("not a valid bookmark".data(using: .utf8)!, forKey: key)
        let store = ExportDirectoryBookmarkStore(defaults: defaults, key: key)

        #expect(store.restoreDirectoryURL() == nil)
    }
}

// MARK: - ExportSaveService ファイル名ユーティリティ Tests

@Suite("ExportSaveService ファイル名ユーティリティ")
struct ExportSaveServiceFileNameTests {

    @Test("使用できない文字をアンダースコアに置換する")
    func sanitizeReplacesInvalidCharacters() {
        let sanitized = ExportSaveService.sanitizeFileName("2026/07/12 会議:メモ")
        #expect(!sanitized.contains("/"))
        #expect(!sanitized.contains(":"))
    }

    @Test("前後の空白はトリムされる")
    func sanitizeTrimsWhitespace() {
        let sanitized = ExportSaveService.sanitizeFileName("  タイトル  ")
        #expect(sanitized == "タイトル")
    }

    @Test("サニタイズ後に空文字になる場合はフォールバック名になる")
    func sanitizeFallsBackWhenEmpty() {
        let sanitized = ExportSaveService.sanitizeFileName("///:::")
        #expect(!sanitized.isEmpty)
    }

    @Test("タイトルと日付からファイル名を生成する")
    func suggestedFileNameIncludesTitleAndDate() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 12
        components.hour = 9
        components.minute = 30
        components.second = 0
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!

        let fileName = ExportSaveService.suggestedFileName(title: "Meeting", date: date)

        #expect(fileName.hasPrefix("Meeting_"))
        #expect(fileName.contains("20260712"))
    }
}
