import Testing
import Foundation
@testable import SokkiKit

/// `KeychainService` の CRUD 往復テスト（TASK-23）。
///
/// 実 Keychain を使う（`SecItemAdd` 等は同期・スレッドセーフな C API で、SPM のテスト
/// 実行はサンドボックス外のため、CI ローカル実行では通常アクセスできる）。本番コードと
/// 衝突しないよう、テスト専用の `kSecAttrService` 名（テストごとに UUID を混ぜた一意な
/// 文字列）を使う。各テストは末尾で必ず `delete` して後始末する
/// （`defer` を使い、途中の `#expect` 失敗時にも確実にクリーンアップする）。
///
/// CI 環境で Keychain が使えない場合への備え: 本テストが失敗する場合でも、
/// `APIKeyChecking`/将来の `APIKeyProviding` はどちらも protocol 注入点として既に
/// 分離されているため（`MockAPIKeyChecking` 等）、`TranslationCoordinator` 等の
/// 上位テストは実 Keychain に依存していない。KeychainService 自体のテストのみ実
/// Keychain 前提とし、in-memory モックは導入しない（Security framework の薄いラッパー
/// であり、モック化すると実装の正しさを検証できなくなるため）。
@Suite("KeychainService CRUD 往復")
struct KeychainServiceTests {
    /// テストごとに専用の service 名を使い、並行実行や他テストとの干渉を避ける。
    private func makeService(_ testName: String = #function) -> KeychainService {
        KeychainService(service: "com.sokki.test.keychain-service.\(testName).\(UUID().uuidString)")
    }

    @Test("store → retrieve で保存した値がそのまま取得できる")
    func storeThenRetrieveRoundTrips() throws {
        let service = makeService()
        defer { try? service.delete(for: "geminiLive") }

        try service.store("sk-test-12345", for: "geminiLive")
        let retrieved = try service.retrieve(for: "geminiLive")

        #expect(retrieved == "sk-test-12345")
    }

    @Test("未登録の providerID の retrieve は nil を返す（throw しない）")
    func retrieveMissingKeyReturnsNil() throws {
        let service = makeService()

        let retrieved = try service.retrieve(for: "geminiLive")

        #expect(retrieved == nil)
    }

    @Test("同一 providerID への再 store は upsert される（重複エラーにならない）")
    func storeTwiceUpsertsValue() throws {
        let service = makeService()
        defer { try? service.delete(for: "geminiLive") }

        try service.store("first-value", for: "geminiLive")
        try service.store("second-value", for: "geminiLive")

        #expect(try service.retrieve(for: "geminiLive") == "second-value")
    }

    @Test("delete 後は retrieve が nil を返す")
    func deleteRemovesValue() throws {
        let service = makeService()
        // `delete`（テスト対象の呼び出し）自体が失敗した場合でも項目を残さないよう、
        // store の前に defer を設定しておく。
        defer { try? service.delete(for: "geminiLive") }

        try service.store("to-be-deleted", for: "geminiLive")
        try service.delete(for: "geminiLive")

        #expect(try service.retrieve(for: "geminiLive") == nil)
    }

    @Test("未登録の providerID への delete は冪等に成功する（throw しない）")
    func deleteMissingKeyIsIdempotent() throws {
        let service = makeService()

        // 一度も store していない providerID を delete してもエラーにならない
        // （throw すればテスト関数の `throws` 経由で自動的に失敗する）。
        try service.delete(for: "neverStored")
    }

    @Test("providerID ごとにキーが分離される（他 providerID の値に影響しない）")
    func keysAreIsolatedPerProviderID() throws {
        let service = makeService()
        defer {
            try? service.delete(for: "geminiLive")
            try? service.delete(for: "googleCloudV3")
        }

        try service.store("geminiLive-key", for: "geminiLive")
        try service.store("google-cloud-key", for: "googleCloudV3")

        #expect(try service.retrieve(for: "geminiLive") == "geminiLive-key")
        #expect(try service.retrieve(for: "googleCloudV3") == "google-cloud-key")
    }

    // MARK: - hasKey（APIKeyChecking 適合）

    @Test("hasKey は未登録→登録→削除の遷移で false→true→false になる")
    func hasKeyReflectsTransitions() throws {
        let service = makeService()
        // 途中の `#expect` 失敗や `delete`（テスト対象）自体の失敗でも項目を残さない。
        defer { try? service.delete(for: "geminiLive") }
        let checking: any APIKeyChecking = service

        #expect(checking.hasKey(for: "geminiLive") == false)

        try service.store("some-key", for: "geminiLive")
        #expect(checking.hasKey(for: "geminiLive") == true)

        try service.delete(for: "geminiLive")
        #expect(checking.hasKey(for: "geminiLive") == false)
    }

    // MARK: - apiKey(for:)（将来の APIKeyProviding 適合に向けた注入点）

    @Test("apiKey(for:) は登録済みの実キーを返し、未登録なら nil を返す")
    func apiKeyForReturnsStoredValueOrNil() async throws {
        let service = makeService()
        defer { try? service.delete(for: "geminiLive") }

        #expect(await service.apiKey(for: "geminiLive") == nil)

        try service.store("real-secret-key", for: "geminiLive")
        #expect(await service.apiKey(for: "geminiLive") == "real-secret-key")
    }
}
