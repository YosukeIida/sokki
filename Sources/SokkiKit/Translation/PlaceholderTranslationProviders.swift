import Foundation

/// TASK-18（`AppleTranslationProvider` 実装）マージまでの DI プレースホルダ。
///
/// 常に `languagePairUnsupported` を throw する。翻訳トグルを ON にしても実際の
/// オンデバイス翻訳は起動しない ＝ 誤って「翻訳できているつもり」の状態を作らない
/// （`TranslationCoordinator.activate` は `prepare()` 失敗時に必ず `teardown()` して
/// `active` を `nil` のままにするため、fail-closed の性質を壊さない）。
/// TASK-18 完了後、`AppDependencyContainer` の生成箇所を実装へ差し替える。
actor PlaceholderAppleTranslationProvider: TranslationProvider {
    nonisolated let providerID = "apple"
    nonisolated let isOnDevice = true

    func prepare(source: Locale.Language, target: Locale.Language) async throws {
        throw TranslationProviderError.languagePairUnsupported(
            source: source.maximalIdentifier,
            target: target.maximalIdentifier
        )
    }

    func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func teardown() async {}
}

/// TASK-23（Keychain 実装）マージまでの `APIKeyChecking` プレースホルダ。
///
/// 常にキー無しを返す（fail-closed）。BYO プロバイダを明示選択しても
/// `TranslationGate.evaluate` が `.missingApiKey` で拒否するため、Keychain 実装が
/// 無い間はクラウド送信が発生しない。
struct PlaceholderAPIKeyChecking: APIKeyChecking {
    func hasKey(for providerID: String) -> Bool { false }
}
