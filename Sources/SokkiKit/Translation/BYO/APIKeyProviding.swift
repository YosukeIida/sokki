import Foundation

/// BYO クラウドキーの実体取得。単一アクセス点に閉じることで `grep APIKeyProviding` で
/// キー参照箇所を全列挙できるようにする。
///
/// `APIKeyChecking`（`TranslationProvider.swift` 定義。存在確認のみ・Gate/Coordinator が
/// 同期参照）とは役割が異なる: こちらは provider が `prepare()` 時に実キー文字列を取得する
/// ための抽象で、`async` かつ値そのものを返す。TASK-23 の Keychain 実装がこの protocol に
/// 適合する形へ差し替わる想定（現状の実装は平文でよい）。
public protocol APIKeyProviding: Sendable {
    /// 指定 `providerID`（= `TranslationProviderKind.rawValue`）の実キーを取得する。
    /// 未登録なら `nil`。
    func apiKey(for providerID: String) async -> String?
}
