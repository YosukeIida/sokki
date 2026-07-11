import AppKit
import Foundation
import UniformTypeIdentifiers

/// エクスポートしたテキストを NSSavePanel 経由でディスクに保存するサービス。
/// 保存先ディレクトリは ExportDirectoryBookmarkStore で記憶し、次回の初期位置として復元する。
@MainActor
struct ExportSaveService {
    private let bookmarkStore: ExportDirectoryBookmarkStore

    init(bookmarkStore: ExportDirectoryBookmarkStore = ExportDirectoryBookmarkStore()) {
        self.bookmarkStore = bookmarkStore
    }

    /// NSSavePanel を表示してテキストを書き出す。
    /// - Returns: 保存できたファイルの URL。キャンセル・書き込み失敗時は nil。
    func save(text: String, suggestedFileName: String, contentType: UTType) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true

        // 前回保存先の復元。sandbox 化した場合に備え、パネルへ渡す前に
        // security-scoped リソースへのアクセスを宣言しておく（非 sandbox では
        // start が false を返しても実害がないため、そのまま続行する）。
        let restoredDirectory = bookmarkStore.restoreDirectoryURL()
        let isAccessingRestoredDirectory = restoredDirectory?.startAccessingSecurityScopedResource() ?? false
        defer {
            if isAccessingRestoredDirectory {
                restoredDirectory?.stopAccessingSecurityScopedResource()
            }
        }
        panel.directoryURL = restoredDirectory

        guard await panel.begin() == .OK, let url = panel.url else { return nil }

        let isAccessingTarget = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessingTarget {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        // 次回の初期位置として、選択されたファイルの親ディレクトリを記憶する。
        bookmarkStore.save(directoryURL: url.deletingLastPathComponent())
        return url
    }

    /// セッションタイトルと日付からファイル名（拡張子なし）を生成する。
    nonisolated static func suggestedFileName(title: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "\(sanitizeFileName(title))_\(formatter.string(from: date))"
    }

    /// ファイル名に使えない文字（`/` `:` など）を `_` に置き換える。
    nonisolated static func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "sokki_export" : trimmed
    }
}
