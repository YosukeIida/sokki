import Foundation

/// エクスポート保存先ディレクトリを Security-Scoped Bookmark として記憶し、
/// 次回の NSSavePanel 初期位置に復元するためのストア。
///
/// このアプリは現状 App Sandbox 無効だが、将来 sandbox を有効化した際にそのまま
/// 動作するよう `.withSecurityScope` での生成・解決を優先し、失敗時のみ通常の
/// ブックマークにフォールバックする2段構えにしている。
struct ExportDirectoryBookmarkStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "sokki.exportDirectoryBookmark") {
        self.defaults = defaults
        self.key = key
    }

    /// 保存済みブックマークからディレクトリ URL を復元する。未保存・壊れた Data の場合は nil。
    /// 解決結果が stale だった場合は再生成して保存し直す。
    func restoreDirectoryURL() -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let (url, isStale) = resolve(data) else { return nil }

        if isStale {
            save(directoryURL: url)
        }
        return url
    }

    /// ディレクトリ URL をブックマークとして保存する。
    func save(directoryURL: URL) {
        guard let data = makeBookmarkData(for: directoryURL) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: Private

    /// `.withSecurityScope` を優先し、失敗したら通常のブックマークにフォールバックする。
    private func makeBookmarkData(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// 復元も生成と同様に `.withSecurityScope` → 通常ブックマークの順で試す。
    private func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return (url, isStale)
        }

        isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return (url, isStale)
        }

        return nil
    }
}
