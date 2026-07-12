import Testing
import Foundation
@testable import SokkiKit

// MARK: - テスト補助

/// スレッド安全な収集箱（`@Sendable` な resume/completion クロージャから書き込むため）。
private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T
    init(_ initial: T) { storage = initial }
    var value: T { lock.withLock { storage } }
    func mutate(_ body: (inout T) -> Void) { lock.withLock { body(&storage) } }
}

/// `AppleTranslationSession` のモック。呼び出し順・回数を記録し、任意でエラーを注入する。
/// 実 `TranslationSession` 非依存で drain ループのロジックを検証するための seam。
private actor MockAppleSession: AppleTranslationSession {
    private(set) var prepareCallCount = 0
    private(set) var translateBatches: [[AppleTranslationRequest]] = []
    private var prepareError: Error?
    private var translateError: Error?

    init(prepareError: Error? = nil, translateError: Error? = nil) {
        self.prepareError = prepareError
        self.translateError = translateError
    }

    func prepareTranslation() async throws {
        prepareCallCount += 1
        if let prepareError { throw prepareError }
    }

    func translate(_ requests: [AppleTranslationRequest]) async throws -> [AppleTranslationResponse] {
        translateBatches.append(requests)
        if let translateError { throw translateError }
        // clientID をエコーバックし、targetText は "T:" 前置で決定的に返す。
        return requests.map {
            AppleTranslationResponse(targetText: "T:\($0.sourceText)", clientID: $0.clientID)
        }
    }
}

private enum SampleError: Error, Equatable { case boom }

@Suite("AppleTranslationBridge drain ループ")
struct AppleTranslationBridgeTests {

    // 入力→翻訳呼び出し→出力の順序保証、および複数ジョブの逐次処理。
    @Test("ジョブは投入順に session.translate へ渡り、応答が resume へ順に返る")
    func jobsDrainInOrder() async {
        let session = MockAppleSession()
        let (stream, continuation) = AsyncStream<HostMessage>.makeStream(bufferingPolicy: .unbounded)
        let collected = LockedBox<[[AppleTranslationResponse]]>([])

        continuation.yield(.job(
            requests: [AppleTranslationRequest(sourceText: "one", clientID: "id-1")],
            resume: { responses in collected.mutate { $0.append(responses) } },
            fail: { _ in }
        ))
        continuation.yield(.job(
            requests: [AppleTranslationRequest(sourceText: "two", clientID: "id-2")],
            resume: { responses in collected.mutate { $0.append(responses) } },
            fail: { _ in }
        ))
        continuation.finish()   // teardown 相当: ストリーム終了で drain ループも終わる。

        await TranslationSessionBridge.runDrainLoop(messages: stream, session: session)

        let batches = await session.translateBatches
        #expect(batches.count == 2)
        #expect(batches[0].first?.sourceText == "one")
        #expect(batches[1].first?.sourceText == "two")

        let out = collected.value
        #expect(out.count == 2)
        #expect(out[0].first == AppleTranslationResponse(targetText: "T:one", clientID: "id-1"))
        #expect(out[1].first == AppleTranslationResponse(targetText: "T:two", clientID: "id-2"))
    }

    // ストリーム終了で drain ループが確実に戻る（teardown で drain 停止）。
    @Test("ストリーム finish で runDrainLoop が戻る（teardown による drain 停止）")
    func streamFinishStopsDrain() async {
        let session = MockAppleSession()
        let (stream, continuation) = AsyncStream<HostMessage>.makeStream(bufferingPolicy: .unbounded)
        let done = LockedBox(false)

        continuation.yield(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in done.mutate { $0 = true } },
            fail: { _ in }
        ))
        continuation.finish()

        // finish 済みのストリームなので runDrainLoop はハングせず戻ること（暗黙のタイムアウトは
        // Swift Testing 側で検出）。
        await TranslationSessionBridge.runDrainLoop(messages: stream, session: session)
        #expect(done.value == true)
        #expect(await session.translateBatches.count == 1)
    }

    // prepareOnly: DL 同意経路。session.prepareTranslation を1度呼び、completion(nil)。
    @Test("prepareOnly は session.prepareTranslation を呼び completion(nil) を返す")
    func prepareOnlySucceeds() async {
        let session = MockAppleSession()
        let (stream, continuation) = AsyncStream<HostMessage>.makeStream(bufferingPolicy: .unbounded)
        let receivedError = LockedBox<Error??>(.some(nil))   // 外側 optional=未設定

        continuation.yield(.prepareOnly(completion: { error in
            receivedError.mutate { $0 = .some(error) }
        }))
        continuation.finish()

        await TranslationSessionBridge.runDrainLoop(messages: stream, session: session)

        #expect(await session.prepareCallCount == 1)
        // completion が呼ばれ、error は nil。
        if case .some(let inner) = receivedError.value {
            #expect(inner == nil)
        } else {
            Issue.record("completion が呼ばれていない")
        }
    }

    // prepareOnly のエラーは completion(error) に伝播。
    @Test("prepareTranslation の throw は completion(error) に伝播する")
    func prepareOnlyPropagatesError() async {
        let session = MockAppleSession(prepareError: SampleError.boom)
        let (stream, continuation) = AsyncStream<HostMessage>.makeStream(bufferingPolicy: .unbounded)
        let received = LockedBox<Error?>(nil)

        continuation.yield(.prepareOnly(completion: { error in
            received.mutate { $0 = error }
        }))
        continuation.finish()

        await TranslationSessionBridge.runDrainLoop(messages: stream, session: session)
        #expect((received.value as? SampleError) == .boom)
    }

    // job の翻訳エラーは fail(error) に伝播し、resume は呼ばれない。
    @Test("translate の throw は fail(error) に伝播し resume は呼ばれない")
    func jobPropagatesError() async {
        let session = MockAppleSession(translateError: SampleError.boom)
        let (stream, continuation) = AsyncStream<HostMessage>.makeStream(bufferingPolicy: .unbounded)
        let failed = LockedBox<Error?>(nil)
        let resumed = LockedBox(false)

        continuation.yield(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in resumed.mutate { $0 = true } },
            fail: { error in failed.mutate { $0 = error } }
        ))
        continuation.finish()

        await TranslationSessionBridge.runDrainLoop(messages: stream, session: session)
        #expect((failed.value as? SampleError) == .boom)
        #expect(resumed.value == false)
    }
}
