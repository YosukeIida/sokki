import Foundation
import Translation
@testable import SokkiKit

/// 固定の `LanguageAvailability.Status` を返す注入可能な可用性チェッカ。
struct MockAvailability: AvailabilityChecking {
    let stub: LanguageAvailability.Status

    func status(from: Locale.Language, to: Locale.Language) async -> LanguageAvailability.Status {
        stub
    }
}

/// 登録済みキー集合を持つ注入可能な API キーチェッカ。
struct MockAPIKeyChecking: APIKeyChecking {
    let keys: Set<String>

    init(keys: Set<String> = []) { self.keys = keys }

    func hasKey(for providerID: String) -> Bool { keys.contains(providerID) }
}
