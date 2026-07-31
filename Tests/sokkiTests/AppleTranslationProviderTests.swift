import Testing
import Foundation
import Translation
@testable import SokkiKit

// MARK: - テスト補助

/// `AppleTranslationHosting` のモックホスト。世代を採番し、enqueue を即時 or 遅延で完了させる。
/// 実 `.translationTask` 常駐ループなしで provider の `prepare`/`translateStream`/`teardown` を検証する。
@MainActor
private final class MockAppleHost: AppleTranslationHosting {
    private(set) var setLanguagesCallCount = 0
    private(set) var endSessionCallCount = 0
    private(set) var prepareOnlyCallCount = 0
    private(set) var jobBatches: [[AppleTranslationRequest]] = []
    private var generationCounter: UInt64 = 0

    /// `awaitReady` に注入するエラー（timeout/supersede シミュレーション）。`nil` なら即 ready。
    var awaitReadyError: Error?
    /// prepareOnly（DL 同意）に注入するエラー。`nil` なら成功。
    var prepareOnlyError: Error?
    /// job（翻訳）に注入するエラー。`nil` なら成功。
    var jobError: Error?
    /// job 応答の clientID を差し替える（MINOR (a): 不一致検証用）。`nil` なら要求 clientID をエコー。
    var overrideResponseClientID: String?
    /// true の間は enqueue を即完了せず保持する（in-flight teardown 再現用）。
    var deferCompletion = false

    private var heldJobs: [HostMessage] = []
    var heldCount: Int { heldJobs.count }

    func setLanguages(source: Locale.Language, target: Locale.Language) -> UInt64 {
        setLanguagesCallCount += 1
        generationCounter += 1
        return generationCounter
    }

    func awaitReady(generation: UInt64, timeout: Duration) async throws {
        if let awaitReadyError { throw awaitReadyError }
    }

    func enqueue(_ message: HostMessage, generation: UInt64) {
        if deferCompletion {
            heldJobs.append(message)
            return
        }
        complete(message)
    }

    func endSession() {
        endSessionCallCount += 1
        let held = heldJobs
        heldJobs.removeAll()
        for message in held { fail(message, CancellationError()) }
    }

    /// 保持中のジョブを成功完了させる（遅延 → 成功の検証用）。
    func flushHeld() {
        let held = heldJobs
        heldJobs.removeAll()
        for message in held { complete(message) }
    }

    private func complete(_ message: HostMessage) {
        switch message {
        case .prepareOnly(let completion):
            prepareOnlyCallCount += 1
            completion(prepareOnlyError)
        case .job(let requests, let resume, let fail):
            jobBatches.append(requests)
            if let jobError {
                fail(jobError)
                return
            }
            resume(requests.map {
                AppleTranslationResponse(
                    targetText: "T:\($0.sourceText)",
                    clientID: overrideResponseClientID ?? $0.clientID
                )
            })
        }
    }

    private func fail(_ message: HostMessage, _ error: Error) {
        switch message {
        case .prepareOnly(let completion): completion(error)
        case .job(_, _, let failClosure): failClosure(error)
        }
    }
}

private enum SampleError: Error, Equatable { case declined }

@Suite("AppleTranslationProvider")
@MainActor
struct AppleTranslationProviderTests {

    private let ja = Locale.Language(identifier: "ja")
    private let en = Locale.Language(identifier: "en")

    private func makeProvider(
        status: LanguageAvailability.Status,
        host: MockAppleHost
    ) -> AppleTranslationProvider {
        AppleTranslationProvider(
            host: host,
            availability: MockAvailability(stub: status),
            readyTimeout: .seconds(1)
        )
    }

    // 監査タグ: providerID / isOnDevice。Gate/Router が nonisolated に読む。
    @Test("providerID は apple、isOnDevice は true")
    func auditTags() {
        let provider = makeProvider(status: .installed, host: MockAppleHost())
        #expect(provider.providerID == "apple")
        #expect(provider.isOnDevice == true)
    }

    // .installed: 言語設定 + ready 確認のみ。DL 同意は出さない。
    @Test("prepare(.installed) は setLanguages と ready 確認のみで DL 同意を出さない")
    func prepareInstalled() async throws {
        let host = MockAppleHost()
        let provider = makeProvider(status: .installed, host: host)
        try await provider.prepare(source: ja, target: en)
        #expect(host.setLanguagesCallCount == 1)
        #expect(host.prepareOnlyCallCount == 0)
    }

    // .supported: 言語設定 + ready 確認 + DL 同意プロンプト。
    @Test("prepare(.supported) は ready 確認後に DL 同意プロンプトを出す")
    func prepareSupportedRequestsDownload() async throws {
        let host = MockAppleHost()
        let provider = makeProvider(status: .supported, host: host)
        try await provider.prepare(source: ja, target: en)
        #expect(host.setLanguagesCallCount == 1)
        #expect(host.prepareOnlyCallCount == 1)
    }

    // .supported で DL 同意が失敗 → prepare が throw。
    @Test("prepare(.supported) の DL 同意失敗は throw する")
    func prepareSupportedDownloadFailureThrows() async {
        let host = MockAppleHost()
        host.prepareOnlyError = TranslationProviderError.modelNotDownloaded
        let provider = makeProvider(status: .supported, host: host)
        await #expect(throws: TranslationProviderError.modelNotDownloaded) {
            try await provider.prepare(source: self.ja, target: self.en)
        }
    }

    // MAJOR-2: prepare は closure ready を待つ。ready 失敗（timeout/supersede）で throw。
    @Test("prepare は awaitReady 失敗で throw する（closure 起動を確認する）")
    func prepareWaitsForReady() async {
        let host = MockAppleHost()
        host.awaitReadyError = TranslationProviderError.providerError("not ready")
        let provider = makeProvider(status: .installed, host: host)
        await #expect(throws: TranslationProviderError.self) {
            try await provider.prepare(source: self.ja, target: self.en)
        }
        // ready 未確認なので DL 同意も出ない。
        #expect(host.prepareOnlyCallCount == 0)
    }

    // .unsupported: languagePairUnsupported を throw（言語コード付き）。
    @Test("prepare(.unsupported) は languagePairUnsupported を throw する")
    func prepareUnsupportedThrows() async {
        let host = MockAppleHost()
        let provider = makeProvider(status: .unsupported, host: host)
        do {
            try await provider.prepare(source: ja, target: en)
            Issue.record("throw されなかった")
        } catch let error as TranslationProviderError {
            #expect(error == .languagePairUnsupported(
                source: ja.maximalIdentifier, target: en.maximalIdentifier))
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
        #expect(host.setLanguagesCallCount == 0)
    }

    // translateStream: 入力 id をエコーバックし、原文行に対応付く出力を返す。
    @Test("translateStream は入力 id をエコーバックして訳文を返す")
    func translateStreamEchoesID() async throws {
        let host = MockAppleHost()
        let provider = makeProvider(status: .installed, host: host)
        try await provider.prepare(source: ja, target: en)

        let id1 = UUID()
        let id2 = UUID()
        let (inputs, inputCont) = AsyncStream<TranslationInput>.makeStream()
        inputCont.yield(TranslationInput(id: id1, text: "hello", sourceTime: 0))
        inputCont.yield(TranslationInput(id: id2, text: "world", sourceTime: 1))
        inputCont.finish()

        let outputs = await provider.translateStream(inputs)
        var results: [TranslationOutput] = []
        for try await output in outputs {
            results.append(output)
        }

        #expect(results.count == 2)
        #expect(results[0].id == id1)
        #expect(results[0].translatedText == "T:hello")
        #expect(results[0].isConcluded == true)
        #expect(results[1].id == id2)
        #expect(results[1].translatedText == "T:world")
        #expect(host.jobBatches.count == 2)
    }

    // MINOR (a): 応答 clientID が要求 id と不一致なら providerError で fail-closed。
    @Test("translateStream は clientID 不一致で providerError を throw する")
    func translateStreamClientIDMismatchThrows() async throws {
        let host = MockAppleHost()
        host.overrideResponseClientID = UUID().uuidString   // 別 id を返させる。
        let provider = makeProvider(status: .installed, host: host)
        try await provider.prepare(source: ja, target: en)

        let (inputs, inputCont) = AsyncStream<TranslationInput>.makeStream()
        inputCont.yield(TranslationInput(id: UUID(), text: "hello", sourceTime: 0))
        inputCont.finish()

        let outputs = await provider.translateStream(inputs)
        var caught: Error?
        do {
            for try await _ in outputs {}
        } catch {
            caught = error
        }
        if case .providerError = (caught as? TranslationProviderError) {
            // OK
        } else {
            Issue.record("providerError が throw されなかった: \(String(describing: caught))")
        }
    }

    // teardown: ホストの endSession を呼び session を手放す。
    @Test("teardown は host.endSession を呼ぶ")
    func teardownEndsSession() async {
        let host = MockAppleHost()
        let provider = makeProvider(status: .installed, host: host)
        await provider.teardown()
        #expect(host.endSessionCallCount == 1)
    }

    // MINOR (b) / MAJOR-1: in-flight ジョブ中に teardown → 継続がリークせずストリームが終了する。
    @Test("in-flight ジョブ中の teardown で継続リークせずストリームが終了する")
    func inFlightTeardownDoesNotLeak() async throws {
        let host = MockAppleHost()
        let provider = makeProvider(status: .installed, host: host)
        try await provider.prepare(source: ja, target: en)

        host.deferCompletion = true   // 以降の enqueue を保持して in-flight を作る。

        let (inputs, inputCont) = AsyncStream<TranslationInput>.makeStream()
        inputCont.yield(TranslationInput(id: UUID(), text: "hello", sourceTime: 0))
        // inputs は finish しない（ジョブが in-flight のまま teardown される状況）。

        let outputs = await provider.translateStream(inputs)
        let consumer = Task { () -> Error? in
            do {
                for try await _ in outputs {}
                return nil
            } catch {
                return error
            }
        }

        // ジョブが host に保持される（= runBatch の継続が in-flight）まで待つ。
        await waitUntil { host.heldCount >= 1 }

        await provider.teardown()   // endSession が保持ジョブを CancellationError で解放。

        let caught = await consumer.value   // ハングせず終了すること（= 継続リークなし）。
        #expect(caught is CancellationError)
    }

    // MARK: helper

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
