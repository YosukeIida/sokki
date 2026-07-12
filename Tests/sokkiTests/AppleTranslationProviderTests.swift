import Testing
import Foundation
import Translation
@testable import SokkiKit

// MARK: - テスト補助

/// `AppleTranslationHosting` のモックホスト。enqueue されたメッセージを **即時** 完了させ、
/// 実 `.translationTask` 常駐ループなしで provider の `prepare`/`translateStream`/`teardown` を
/// 検証できるようにする。
@MainActor
private final class MockAppleHost: AppleTranslationHosting {
    private(set) var setLanguagesCallCount = 0
    private(set) var clearConfigurationCallCount = 0
    private(set) var prepareOnlyCallCount = 0
    private(set) var jobBatches: [[AppleTranslationRequest]] = []

    /// prepareOnly（DL 同意）に注入するエラー。`nil` なら成功。
    var prepareOnlyError: Error?
    /// job（翻訳）に注入するエラー。`nil` なら成功。
    var jobError: Error?

    func setLanguages(source: Locale.Language, target: Locale.Language) {
        setLanguagesCallCount += 1
    }

    func clearConfiguration() {
        clearConfigurationCallCount += 1
    }

    func enqueue(_ message: HostMessage) {
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
            let responses = requests.map {
                AppleTranslationResponse(targetText: "T:\($0.sourceText)", clientID: $0.clientID)
            }
            resume(responses)
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
        AppleTranslationProvider(host: host, availability: MockAvailability(stub: status))
    }

    // 監査タグ: providerID / isOnDevice。Gate/Router が nonisolated に読む。
    @Test("providerID は apple、isOnDevice は true")
    func auditTags() {
        let provider = makeProvider(status: .installed, host: MockAppleHost())
        #expect(provider.providerID == "apple")
        #expect(provider.isOnDevice == true)
    }

    // .installed: 言語設定のみ。DL 同意は出さない。
    @Test("prepare(.installed) は setLanguages のみで DL 同意を出さない")
    func prepareInstalled() async throws {
        let host = MockAppleHost()
        let provider = makeProvider(status: .installed, host: host)
        try await provider.prepare(source: ja, target: en)
        #expect(host.setLanguagesCallCount == 1)
        #expect(host.prepareOnlyCallCount == 0)
    }

    // .supported: 言語設定 + DL 同意プロンプト（prepareTranslation 経路）。
    @Test("prepare(.supported) は setLanguages と DL 同意プロンプトを出す")
    func prepareSupportedRequestsDownload() async throws {
        let host = MockAppleHost()
        let provider = makeProvider(status: .supported, host: host)
        try await provider.prepare(source: ja, target: en)
        #expect(host.setLanguagesCallCount == 1)
        #expect(host.prepareOnlyCallCount == 1)   // モデル DL プロンプト経路
    }

    // .supported で DL 同意が失敗（ユーザー拒否等）→ prepare が throw。
    @Test("prepare(.supported) の DL 同意失敗は throw する")
    func prepareSupportedDownloadFailureThrows() async {
        let host = MockAppleHost()
        host.prepareOnlyError = SampleError.declined
        let provider = makeProvider(status: .supported, host: host)
        await #expect(throws: SampleError.self) {
            try await provider.prepare(source: self.ja, target: self.en)
        }
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
        #expect(host.setLanguagesCallCount == 0)   // 未対応では言語設定しない
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
        // 各確定セグメントは1要素バッチとしてホストへ渡る。
        #expect(host.jobBatches.count == 2)
    }

    // teardown: ホストの clearConfiguration を呼び session を手放す。
    @Test("teardown は host.clearConfiguration を呼ぶ")
    func teardownClearsConfiguration() async {
        let host = MockAppleHost()
        let provider = makeProvider(status: .installed, host: host)
        await provider.teardown()
        #expect(host.clearConfigurationCallCount == 1)
    }
}
