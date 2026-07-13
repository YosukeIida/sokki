import Testing
import Foundation
@testable import SokkiKit

@Suite("DeepLTranslationProvider REST 翻訳（モック transport・実ネットワーク禁止）")
struct DeepLTranslationProviderTests {

    private let ja = Locale.Language(identifier: "ja")
    private let en = Locale.Language(identifier: "en")

    /// 条件が満たされるまで（または timeout まで）待つ。
    private func waitUntil(timeout: Duration = .seconds(3), _ cond: () async -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await cond()) && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeProvider(
        key: String? = "test-key:fx",
        transport: @escaping DeepLTransport
    ) -> DeepLTranslationProvider {
        DeepLTranslationProvider(
            keyProvider: StubAPIKeyProvider(key: key),
            transport: transport,
            sleeper: { _ in }   // テストではリトライ待機をスキップ
        )
    }

    // MARK: - prepare()

    @Test("prepare: キー未設定なら missingAPIKey")
    func prepareMissingKey() async {
        let provider = makeProvider(key: nil) { _ in
            Issue.record("transport should not be called when key is missing")
            return (Data(), URLResponse())
        }
        await #expect(throws: TranslationProviderError.missingAPIKey) {
            try await provider.prepare(source: ja, target: en)
        }
    }

    // MARK: - 正常系: id エコーバック順序

    @Test("translateStream: 複数入力を id エコーバックしつつ順序どおりに返す")
    func translateStreamEchoesIdsInOrder() async throws {
        let script = ScriptedDeepLTransport([
            .success(text: "Hello"),
            .success(text: "World"),
        ])
        let provider = makeProvider(transport: script.transport)
        try await provider.prepare(source: ja, target: en)

        let (inputs, cont) = AsyncStream<TranslationInput>.makeStream()
        let idA = UUID()
        let idB = UUID()
        cont.yield(TranslationInput(id: idA, text: "こんにちは", sourceTime: 0))
        cont.yield(TranslationInput(id: idB, text: "世界", sourceTime: 1))
        cont.finish()

        var received: [TranslationOutput] = []
        for try await output in await provider.translateStream(inputs) {
            received.append(output)
        }

        #expect(received.map(\.id) == [idA, idB])
        #expect(received.map(\.translatedText) == ["Hello", "World"])
        #expect(received.allSatisfy { $0.isConcluded })

        let requests = await script.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key test-key:fx")
        // Free キー（:fx 接尾辞）は api-free.deepl.com を使う。
        #expect(requests[0].url?.host == "api-free.deepl.com")
    }

    @Test("translateStream: Pro キー（:fx 接尾辞なし）は api.deepl.com を使う")
    func proKeyUsesProEndpoint() async throws {
        let script = ScriptedDeepLTransport([.success(text: "Hi")])
        let provider = makeProvider(key: "pro-key", transport: script.transport)
        try await provider.prepare(source: ja, target: en)

        let (inputs, cont) = AsyncStream<TranslationInput>.makeStream()
        cont.yield(TranslationInput(id: UUID(), text: "やあ", sourceTime: 0))
        cont.finish()

        var received: [TranslationOutput] = []
        for try await output in await provider.translateStream(inputs) { received.append(output) }
        #expect(received.count == 1)

        let requests = await script.recordedRequests
        #expect(requests.first?.url?.host == "api.deepl.com")
    }

    // MARK: - 401 → エラー写像

    @Test("translateStream: 401 は missingAPIKey へ写像されストリームが throw で終わる")
    func unauthorizedMapsToMissingApiKey() async throws {
        let script = ScriptedDeepLTransport([.status(401)])
        let provider = makeProvider(transport: script.transport)
        try await provider.prepare(source: ja, target: en)

        let (inputs, cont) = AsyncStream<TranslationInput>.makeStream()
        cont.yield(TranslationInput(id: UUID(), text: "こんにちは", sourceTime: 0))
        cont.finish()

        await #expect(throws: TranslationProviderError.missingAPIKey) {
            for try await _ in await provider.translateStream(inputs) {}
        }
    }

    // MARK: - 429 → 1回リトライ

    @Test("translateStream: 429 は1回だけリトライし、成功すれば結果を返す")
    func rateLimitRetriesOnce() async throws {
        let script = ScriptedDeepLTransport([
            .status(429),
            .success(text: "Retried"),
        ])
        let provider = makeProvider(transport: script.transport)
        try await provider.prepare(source: ja, target: en)

        let (inputs, cont) = AsyncStream<TranslationInput>.makeStream()
        let id = UUID()
        cont.yield(TranslationInput(id: id, text: "リトライ", sourceTime: 0))
        cont.finish()

        var received: [TranslationOutput] = []
        for try await output in await provider.translateStream(inputs) { received.append(output) }

        #expect(received.map(\.id) == [id])
        #expect(received.map(\.translatedText) == ["Retried"])
        let requests = await script.recordedRequests
        #expect(requests.count == 2)   // 初回 + リトライ1回
    }

    @Test("translateStream: 429 が2回続いたら2回目でリトライ打ち切り connectionFailed")
    func rateLimitGivesUpAfterOneRetry() async throws {
        let script = ScriptedDeepLTransport([.status(429), .status(429)])
        let provider = makeProvider(transport: script.transport)
        try await provider.prepare(source: ja, target: en)

        let (inputs, cont) = AsyncStream<TranslationInput>.makeStream()
        cont.yield(TranslationInput(id: UUID(), text: "だめ", sourceTime: 0))
        cont.finish()

        await #expect(throws: TranslationProviderError.self) {
            for try await _ in await provider.translateStream(inputs) {}
        }
        let requests = await script.recordedRequests
        #expect(requests.count == 2)   // 1回だけリトライして打ち切り
    }

    // MARK: - 456 → quota exceeded（connectionFailed に混ぜない）

    @Test("translateStream: 456 は quota exceeded として providerError へ写像される（connectionFailed ではない）")
    func quotaExceededMapsToProviderError() async throws {
        let script = ScriptedDeepLTransport([.status(456)])
        let provider = makeProvider(transport: script.transport)
        try await provider.prepare(source: ja, target: en)

        let (inputs, cont) = AsyncStream<TranslationInput>.makeStream()
        cont.yield(TranslationInput(id: UUID(), text: "上限", sourceTime: 0))
        cont.finish()

        await #expect(throws: TranslationProviderError.providerError("DeepL quota exceeded (HTTP 456)")) {
            for try await _ in await provider.translateStream(inputs) {}
        }
        // 456 はリトライ対象外（1回のみ発行）。
        let requests = await script.recordedRequests
        #expect(requests.count == 1)
    }

    // MARK: - teardown / 消費側キャンセルで in-flight リクエストがキャンセルされる

    @Test("translateStream: 出力側の消費キャンセルが進行中リクエストへ伝播する")
    func consumerCancellationPropagatesToInFlightRequest() async throws {
        let hanging = HangingDeepLTransport()
        let provider = makeProvider(transport: hanging.transport)
        try await provider.prepare(source: ja, target: en)

        let (inputs, cont) = AsyncStream<TranslationInput>.makeStream()
        cont.yield(TranslationInput(id: UUID(), text: "止めて", sourceTime: 0))

        let stream = await provider.translateStream(inputs)
        let consumer = Task {
            for try await _ in stream {}
        }

        // リクエストが実際に発行されるまで待つ。
        await waitUntil { await hanging.callCount == 1 }

        // TranslationCoordinator.teardown() が pumpTask.cancel() する経路を模擬。
        consumer.cancel()

        await waitUntil { await hanging.wasCancelled }
        #expect(await hanging.wasCancelled == true)

        cont.finish()
    }

    // MARK: - teardown() は冪等

    @Test("teardown: 複数回呼んでもクラッシュせず、以降 prepare なしでは missingAPIKey")
    func teardownIsIdempotentAndClearsState() async throws {
        let script = ScriptedDeepLTransport([.success(text: "Hi")])
        let provider = makeProvider(transport: script.transport)
        try await provider.prepare(source: ja, target: en)

        await provider.teardown()
        await provider.teardown()   // 冪等性: 2回目もクラッシュしない

        let (inputs, cont) = AsyncStream<TranslationInput>.makeStream()
        cont.yield(TranslationInput(id: UUID(), text: "x", sourceTime: 0))
        cont.finish()

        await #expect(throws: TranslationProviderError.missingAPIKey) {
            for try await _ in await provider.translateStream(inputs) {}
        }
    }
}
