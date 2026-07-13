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
/// `usesGate` を指定すると `translate` を任意のタイミングまで停止させ、in-flight 中の teardown を再現できる。
private actor MockAppleSession: AppleTranslationSession {
    private(set) var prepareCallCount = 0
    private(set) var translateBatches: [[AppleTranslationRequest]] = []
    private var prepareError: Error?
    private var translateError: Error?

    private var gate: CheckedContinuation<Void, Never>?
    private var gateWaiter: CheckedContinuation<Void, Never>?
    private let usesGate: Bool

    init(prepareError: Error? = nil, translateError: Error? = nil, usesGate: Bool = false) {
        self.prepareError = prepareError
        self.translateError = translateError
        self.usesGate = usesGate
    }

    func prepareTranslation() async throws {
        prepareCallCount += 1
        if let prepareError { throw prepareError }
    }

    func translate(_ requests: [AppleTranslationRequest]) async throws -> [AppleTranslationResponse] {
        translateBatches.append(requests)
        if usesGate {
            gateWaiter?.resume()   // translate 到達を通知。
            gateWaiter = nil
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in gate = c }
        }
        if let translateError { throw translateError }
        return requests.map {
            AppleTranslationResponse(targetText: "T:\($0.sourceText)", clientID: $0.clientID)
        }
    }

    /// `translate` が実際に呼ばれるまで待つ（in-flight 到達の確認用）。
    func waitUntilTranslating() async {
        if !translateBatches.isEmpty { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in gateWaiter = c }
    }

    /// 停止中の `translate` を解放する。
    func releaseGate() {
        gate?.resume()
        gate = nil
    }
}

private enum SampleError: Error, Equatable { case boom }

@Suite("AppleTranslationBridge ライフサイクル / drain ループ")
@MainActor
struct AppleTranslationBridgeTests {

    private let ja = Locale.Language(identifier: "ja")
    private let en = Locale.Language(identifier: "en")

    // 入力→翻訳呼び出し→出力の順序保証、および複数ジョブの逐次処理。
    @Test("ジョブは投入順に session.translate へ渡り、応答が resume へ順に返る")
    func jobsDrainInOrder() async {
        let bridge = TranslationSessionBridge()
        let session = MockAppleSession()
        let collected = LockedBox<[[AppleTranslationResponse]]>([])

        let generation = bridge.setLanguages(source: ja, target: en)
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "one", clientID: "id-1")],
            resume: { responses in collected.mutate { $0.append(responses) } },
            fail: { _ in }
        ), generation: generation)
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "two", clientID: "id-2")],
            resume: { responses in collected.mutate { $0.append(responses) } },
            fail: { _ in }
        ), generation: generation)

        let loop = Task {
            await TranslationSessionBridge.runDrainLoop(
                bridge: bridge, session: session, expectedGeneration: bridge.generationSnapshot
            )
        }
        await waitUntil { collected.value.count == 2 }
        bridge.endSession()
        await loop.value

        let batches = await session.translateBatches
        #expect(batches.count == 2)
        #expect(batches[0].first?.sourceText == "one")
        #expect(batches[1].first?.sourceText == "two")

        let out = collected.value
        #expect(out.count == 2)
        #expect(out[0].first == AppleTranslationResponse(targetText: "T:one", clientID: "id-1"))
        #expect(out[1].first == AppleTranslationResponse(targetText: "T:two", clientID: "id-2"))
    }

    // teardown で **待機中の** drain ループが終了する（endSession → runDrainLoop が戻る）。
    @Test("endSession で待機中の runDrainLoop が戻る（teardown による drain 停止）")
    func endSessionStopsDrain() async {
        let bridge = TranslationSessionBridge()
        let session = MockAppleSession()
        let processed = LockedBox(false)

        let generation = bridge.setLanguages(source: ja, target: en)
        // 1件処理させてから、ループが次のジョブを待っている状態で endSession する。
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in processed.mutate { $0 = true } },
            fail: { _ in }
        ), generation: generation)

        let loop = Task {
            await TranslationSessionBridge.runDrainLoop(
                bridge: bridge, session: session, expectedGeneration: bridge.generationSnapshot
            )
        }
        await waitUntil { processed.value }   // ループが起動し次を待機中。
        bridge.endSession()
        await loop.value                       // ハングせず戻れば OK。
        #expect(await session.translateBatches.count == 1)
    }

    // MAJOR-1: キュー済み（未 drain）ジョブは endSession で一度だけ CancellationError 完了。
    @Test("endSession はキュー済みジョブを CancellationError で一度だけ失敗完了させる")
    func endSessionCancelsQueuedJobs() async {
        let bridge = TranslationSessionBridge()
        let failCount = LockedBox(0)
        let lastError = LockedBox<Error?>(nil)
        let resumeCount = LockedBox(0)

        let generation = bridge.setLanguages(source: ja, target: en)
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in resumeCount.mutate { $0 += 1 } },
            fail: { error in failCount.mutate { $0 += 1 }; lastError.mutate { $0 = error } }
        ), generation: generation)

        bridge.endSession()
        bridge.endSession()   // 冪等: 二重呼び出しでも二重完了しない。

        #expect(failCount.value == 1)
        #expect(resumeCount.value == 0)
        #expect(lastError.value is CancellationError)
    }

    // MAJOR-1: 世代失効後の enqueue は即座に CancellationError 完了（継続リーク防止）。
    @Test("teardown 後の enqueue は即キャンセル完了する")
    func enqueueAfterTeardownCancelsImmediately() async {
        let bridge = TranslationSessionBridge()
        let generation = bridge.setLanguages(source: ja, target: en)
        bridge.endSession()

        let failed = LockedBox<Error?>(nil)
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in },
            fail: { error in failed.mutate { $0 = error } }
        ), generation: generation)

        #expect(failed.value is CancellationError)
    }

    // MAJOR-1: in-flight（処理中）ジョブも endSession で一度だけキャンセルされ、
    // その後 session が復帰しても二重完了しない。
    @Test("in-flight ジョブの teardown は一度だけ CancellationError、復帰後も二重完了しない")
    func endSessionCancelsInFlightOnce() async {
        let bridge = TranslationSessionBridge()
        let session = MockAppleSession(usesGate: true)
        let failCount = LockedBox(0)
        let resumeCount = LockedBox(0)
        let lastError = LockedBox<Error?>(nil)

        let generation = bridge.setLanguages(source: ja, target: en)
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in resumeCount.mutate { $0 += 1 } },
            fail: { error in failCount.mutate { $0 += 1 }; lastError.mutate { $0 = error } }
        ), generation: generation)

        let loop = Task {
            await TranslationSessionBridge.runDrainLoop(
                bridge: bridge, session: session, expectedGeneration: bridge.generationSnapshot
            )
        }
        await session.waitUntilTranslating()   // translate が in-flight に入るまで待つ。

        bridge.endSession()                     // in-flight を CancellationError で完了。
        await session.releaseGate()             // session を復帰させ、finish を試みさせる。
        await loop.value

        #expect(failCount.value == 1)           // 一度だけ失敗完了。
        #expect(resumeCount.value == 0)         // 復帰後の resume は起きない（二重完了なし）。
        #expect(lastError.value is CancellationError)
    }

    // prepareOnly: DL 同意経路。session.prepareTranslation を1度呼び completion(nil)。
    @Test("prepareOnly は session.prepareTranslation を呼び completion(nil) を返す")
    func prepareOnlySucceeds() async {
        let bridge = TranslationSessionBridge()
        let session = MockAppleSession()
        let receivedError = LockedBox<Error??>(.none)   // .none=未呼び出し / .some(nil)=成功

        let generation = bridge.setLanguages(source: ja, target: en)
        bridge.enqueue(.prepareOnly(completion: { error in
            receivedError.mutate { $0 = .some(error) }
        }), generation: generation)

        let loop = Task {
            await TranslationSessionBridge.runDrainLoop(
                bridge: bridge, session: session, expectedGeneration: bridge.generationSnapshot
            )
        }
        await waitUntil { if case .some = receivedError.value { return true } else { return false } }
        bridge.endSession()
        await loop.value

        #expect(await session.prepareCallCount == 1)
        if case .some(let inner) = receivedError.value {
            #expect(inner == nil)
        } else {
            Issue.record("completion が呼ばれていない")
        }
    }

    // MAJOR-4: prepareTranslation の framework エラーは modelNotDownloaded に正規化される。
    @Test("prepareTranslation の throw は modelNotDownloaded に正規化される")
    func prepareOnlyNormalizesError() async {
        let bridge = TranslationSessionBridge()
        let session = MockAppleSession(prepareError: SampleError.boom)
        let received = LockedBox<Error?>(nil)

        let generation = bridge.setLanguages(source: ja, target: en)
        bridge.enqueue(.prepareOnly(completion: { error in
            received.mutate { $0 = error }
        }), generation: generation)

        let loop = Task {
            await TranslationSessionBridge.runDrainLoop(
                bridge: bridge, session: session, expectedGeneration: bridge.generationSnapshot
            )
        }
        await waitUntil { received.value != nil }
        bridge.endSession()
        await loop.value

        #expect((received.value as? TranslationProviderError) == .modelNotDownloaded)
    }

    // MAJOR-4: translate の framework エラーは providerError に正規化され、resume は呼ばれない。
    @Test("translate の throw は providerError に正規化され resume は呼ばれない")
    func jobNormalizesError() async {
        let bridge = TranslationSessionBridge()
        let session = MockAppleSession(translateError: SampleError.boom)
        let failed = LockedBox<Error?>(nil)
        let resumed = LockedBox(false)

        let generation = bridge.setLanguages(source: ja, target: en)
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in resumed.mutate { $0 = true } },
            fail: { error in failed.mutate { $0 = error } }
        ), generation: generation)

        let loop = Task {
            await TranslationSessionBridge.runDrainLoop(
                bridge: bridge, session: session, expectedGeneration: bridge.generationSnapshot
            )
        }
        await waitUntil { failed.value != nil }
        bridge.endSession()
        await loop.value

        if case .providerError = (failed.value as? TranslationProviderError) {
            // OK: 契約 error に正規化された。
        } else {
            Issue.record("providerError に正規化されていない: \(String(describing: failed.value))")
        }
        #expect(resumed.value == false)
    }

    // BLOCKER (codex 再レビュー): 起動が遅延した旧 closure が「たまたま」現行世代と一致して
    // 古い session を新世代のジョブに使ってしまわないよう、`beginDrain` は closure 構築時点の
    // 世代スナップショット（`expectedGeneration`）と実行時点の現在世代の一致を要求する。
    // 不一致なら一度も drain せず、ready も立てず、session にも一切触れずに終了すること。
    @Test("beginDrain は expectedGeneration が現在の世代と不一致なら即終了する（stale closure 対策）")
    func staleClosureNeverDrains() async {
        let bridge = TranslationSessionBridge()
        let session = MockAppleSession()

        // 「起動が遅延した旧 closure」を模す: 古い世代スナップショットを保持したまま、
        // その後に setLanguages が呼ばれて世代が進んだ状況を作る。
        _ = bridge.setLanguages(source: ja, target: en)
        let staleGeneration = bridge.generationSnapshot
        _ = bridge.setLanguages(source: en, target: ja)   // 世代 supersede。

        await TranslationSessionBridge.runDrainLoop(
            bridge: bridge, session: session, expectedGeneration: staleGeneration
        )

        // stale closure は session に一切触れない（beginDrain が nil を返して即終了するため）。
        #expect(await session.translateBatches.isEmpty)
        #expect(await session.prepareCallCount == 0)
    }

    // MAJOR (codex 再レビュー): 同一言語ペアを再設定しても `Configuration` が Equatable 上
    // 変化しなければ `.translationTask` が再走しない（Apple ドキュメント上、同一 action の
    // 再実行には `invalidate()` で version を進める必要がある）。setLanguages が同一ペアの
    // 再設定を検知して invalidate() 経由で configuration を変化させることを確認する。
    @Test("setLanguages は同一言語ペアの再設定でも configuration を変化させる（invalidate 経由）")
    func setLanguagesInvalidatesOnSamePair() {
        let bridge = TranslationSessionBridge()

        _ = bridge.setLanguages(source: ja, target: en)
        let first = bridge.configuration
        _ = bridge.setLanguages(source: ja, target: en)   // 同一ペアの再設定。
        let second = bridge.configuration

        #expect(first != nil)
        #expect(second != nil)
        #expect(first != second)   // Equatable 上も変化していること（invalidate() の効果）。
    }

    // MAJOR (codex 再レビュー、前回 MAJOR-1: PARTIALLY): setLanguages による世代 supersede は
    // （endSession を経由しなくても）旧世代の pending ジョブを一度だけ CancellationError で
    // 完了させる必要がある。放置すると continuation リークになる。
    @Test("setLanguages は旧世代の pending ジョブを一度だけ CancellationError で失敗完了させる")
    func setLanguagesCancelsOldPendingJobs() {
        let bridge = TranslationSessionBridge()
        let failCount = LockedBox(0)
        let resumeCount = LockedBox(0)
        let lastError = LockedBox<Error?>(nil)

        let oldGeneration = bridge.setLanguages(source: ja, target: en)
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in resumeCount.mutate { $0 += 1 } },
            fail: { error in failCount.mutate { $0 += 1 }; lastError.mutate { $0 = error } }
        ), generation: oldGeneration)

        _ = bridge.setLanguages(source: en, target: ja)   // teardown なしで supersede。

        #expect(failCount.value == 1)
        #expect(resumeCount.value == 0)
        #expect(lastError.value is CancellationError)
    }

    // BLOCKER (codex 再レビュー): View 消失等で drain ループの Task がキャンセルされた場合、
    // 二度と `signalWake()` が来なくても `waitForWake()` に取り残されずループが終了すること。
    @Test("drain ループの Task キャンセルは waitForWake に取り残されず終了する")
    func drainLoopExitsOnTaskCancellation() async {
        let bridge = TranslationSessionBridge()
        let session = MockAppleSession()

        _ = bridge.setLanguages(source: ja, target: en)
        let expectedGeneration = bridge.generationSnapshot

        let loop = Task {
            await TranslationSessionBridge.runDrainLoop(
                bridge: bridge, session: session, expectedGeneration: expectedGeneration
            )
        }
        // ジョブが無いため drain ループは beginDrain 後すぐ waitForWake() で待機に入る。
        // その状態に達するのを少し待ってからキャンセルする。
        try? await Task.sleep(for: .milliseconds(50))
        loop.cancel()

        // teardown 相当の signalWake が二度と来ない状況でも、Task キャンセルにより
        // waitForWake の待機から解放されてループが戻ること（ハングしないこと）。
        await loop.value

        // [NEW]（codex 再レビュー）: ループ終了後に `drainEnded` が configuration を失効させて
        // いなければ、この世代への enqueue は「受理されるが誰も drain しない」ため
        // continuation が永久に完了しない。失効済みなら即座に CancellationError で返る。
        let failed = LockedBox<Error?>(nil)
        bridge.enqueue(.job(
            requests: [AppleTranslationRequest(sourceText: "x", clientID: "id-x")],
            resume: { _ in },
            fail: { error in failed.mutate { $0 = error } }
        ), generation: expectedGeneration)
        #expect(failed.value is CancellationError)
    }

    // MAJOR (codex 再レビュー): `awaitReady` はキャンセルされた `Task.sleep` を `try?` で
    // 握り潰すと、キャンセル後も deadline まで busy-spin して MainActor を占有する。
    // 呼び出し元 Task をキャンセルしたら、`readyTimeout` を待たずに素早く CancellationError で
    // 終わることを確認する（≒10s の readyTimeout に対し十分小さい猶予で完了すること）。
    @Test("awaitReady は呼び出し元 Task のキャンセルで busy-spin せず素早く終わる")
    func awaitReadyPropagatesCancellationPromptly() async {
        let bridge = TranslationSessionBridge()
        // ready にならない世代（beginDrain を一度も呼ばない）を待たせ続ける状況を作る。
        let generation = bridge.setLanguages(source: ja, target: en)

        let waiter = Task {
            try await bridge.awaitReady(generation: generation, timeout: .seconds(10))
        }
        try? await Task.sleep(for: .milliseconds(30))
        waiter.cancel()

        let start = ContinuousClock.now
        let result = await waiter.result
        let elapsed = ContinuousClock.now - start

        // busy-spin していれば ~10s の readyTimeout 近くまでかかる。キャンセルが正しく伝播していれば
        // 数十ms 以内に終わるはず。余裕を持って 1s 未満を要求する。
        #expect(elapsed < .seconds(1))
        switch result {
        case .failure(let error):
            #expect(error is CancellationError)
        case .success:
            Issue.record("キャンセルされたのに成功で終わった")
        }
    }

    // MARK: helper

    /// 条件成立まで MainActor を明け渡して待つ。
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
