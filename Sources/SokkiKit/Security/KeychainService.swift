import Foundation
import Security

/// 翻訳 BYO API キーの Keychain 単一アクセス点（TASK-23 / P25-7）。
///
/// `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete` を直接呼ぶ。
/// Security framework の C API は同期・スレッドセーフなため actor 化せず、状態を持たない
/// `Sendable` な `final class` として実装する（`docs/recap-codebase-analysis.md`
/// 「Keychain サービス」節の `KeychainService`/`KeychainServiceType` を踏襲）。
///
/// `kSecAttrService` に `service`（既定 `"com.sokki.translation-api-key"`）、
/// `kSecAttrAccount` に `providerID`（= `TranslationProviderKind.rawValue`）を用いて
/// プロバイダごとにキーを分離する。`service` を注入可能にしているのはテスト用で、
/// 実 Keychain を汚さないよう専用の service 名を使うため（本番コードは既定値を使う）。
///
/// キー文字列そのものをログ・エラーメッセージに含めないこと。`KeychainError` は
/// `OSStatus` のみを保持する。
public final class KeychainService: Sendable {
    public enum KeychainError: Error, Sendable, Equatable {
        /// `SecItemAdd`/`SecItemUpdate`/`SecItemDelete` が成功以外の `OSStatus` を返した。
        case unexpectedStatus(OSStatus)
        /// 取得したデータを UTF-8 文字列として解釈できなかった、または保存対象を
        /// UTF-8 エンコードできなかった。
        case unexpectedData
    }

    private let service: String

    public init(service: String = "com.sokki.translation-api-key") {
        self.service = service
    }

    // MARK: - CRUD

    /// 値を保存する。既存のキーがあれば `SecItemUpdate` へフォールバックする upsert。
    public func store(_ value: String, for providerID: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }
        let query = baseQuery(for: providerID)
        let attributes: [String: Any] = [kSecValueData as String: data]

        var addQuery = query
        for (key, val) in attributes { addQuery[key] = val }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// 値を取得する。未登録なら `nil`（`errSecItemNotFound` は throw しない）。
    public func retrieve(for providerID: String) throws -> String? {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return value
    }

    /// 削除する。未登録でも冪等に成功扱いにする。
    public func delete(for providerID: String) throws {
        let status = SecItemDelete(baseQuery(for: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// 登録済みか（`retrieve` が非 throw で値を返せるか）。
    public func exists(for providerID: String) -> Bool {
        (try? retrieve(for: providerID)).flatMap { $0 } != nil
    }

    private func baseQuery(for providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
        ]
    }
}

// MARK: - APIKeyChecking

/// Gate/Coordinator が同期的にキー有無だけを照会するための適合
/// （`Sources/SokkiKit/Translation/TranslationProvider.swift` 定義）。
extension KeychainService: APIKeyChecking {
    public func hasKey(for providerID: String) -> Bool {
        exists(for: providerID)
    }
}

// MARK: - 将来の APIKeyProviding 適合に向けた注入点

extension KeychainService {
    /// 指定 `providerID` の実キーを取得する。未登録なら `nil`。
    ///
    /// TASK-22（`feat/task-22-deepl-provider`）で定義された `APIKeyProviding`
    /// （`func apiKey(for providerID: String) async -> String?`）とシグネチャを
    /// 一致させてある。同ブランチのマージ後は `extension KeychainService: APIKeyProviding {}`
    /// を追加するだけで適合できる想定（現時点では本ブランチに `APIKeyProviding` が
    /// 存在しないため、適合宣言自体は行わない）。
    public func apiKey(for providerID: String) async -> String? {
        try? retrieve(for: providerID)
    }
}
