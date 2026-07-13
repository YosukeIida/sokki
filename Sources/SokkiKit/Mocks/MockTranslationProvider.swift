#if DEBUG
import Foundation

/// ルーティング / ライフサイクルテスト用の翻訳プロバイダ。
///
/// - `prepare` / `teardown` の呼び出し回数と引数を記録する。
/// - `shuffleOutput` を指定すると隣接ペアを入れ替えて出力順を決定的に乱し、`id`
///   エコーバックによる原文行との対応付けを検証できる。出力はストリーミング中に随時
///   flush されるため、Coordinator の pump が teardown 前に全件を受け取れる。
/// - `isOnDevice` を切り替えてオンデバイス / クラウドの両経路を模擬できる。
public actor MockTranslationProvider: TranslationProvider {
    public nonisolated let providerID: String
    public nonisolated let isOnDevice: Bool

    private let prepareError: TranslationProviderError?
    private let shuffleOutput: Bool

    public private(set) var prepareCallCount = 0
    public private(set) var teardownCallCount = 0
    public private(set) var preparedSource: Locale.Language?
    public private(set) var preparedTarget: Locale.Language?

    public init(
        providerID: String = "mock",
        isOnDevice: Bool = false,
        prepareError: TranslationProviderError? = nil,
        shuffleOutput: Bool = false
    ) {
        self.providerID = providerID
        self.isOnDevice = isOnDevice
        self.prepareError = prepareError
        self.shuffleOutput = shuffleOutput
    }

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        prepareCallCount += 1
        preparedSource = source
        preparedTarget = target
        if let error = prepareError { throw error }
    }

    public func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error> {
        let shuffle = shuffleOutput
        return AsyncThrowingStream { continuation in
            let task = Task {
                var held: TranslationOutput?
                for await input in inputs {
                    let output = TranslationOutput(
                        id: input.id,
                        translatedText: "translated:\(input.text)",
                        isConcluded: true,
                        sourceTime: input.sourceTime
                    )
                    if shuffle {
                        // 隣接ペアを入れ替えて随時 flush（現在→保留の順で出す）。
                        if let previous = held {
                            continuation.yield(output)
                            continuation.yield(previous)
                            held = nil
                        } else {
                            held = output
                        }
                    } else {
                        continuation.yield(output)
                    }
                }
                if let leftover = held {
                    continuation.yield(leftover)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func teardown() async {
        teardownCallCount += 1
    }
}
#endif
