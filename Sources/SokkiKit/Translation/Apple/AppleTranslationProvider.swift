import Foundation
import Translation

/// オンデバイス既定の翻訳プロバイダ（Apple Translation Framework）。
///
/// `TranslationSession` は直接生成できず `.translationTask` closure 経由でしか取得できないため、
/// 常駐ホスト（`TranslationSessionBridge` + `TranslationHostView`）へジョブを委譲する。session は
/// closure 内に閉じ込め、この actor へは越境させない。actor↔MainActor を渡るのは素の String 値
/// だけ（`docs/translation-architecture.md` §0 訂正 #1 / §8.3 / D-15）。
///
/// - `isOnDevice == true` なのでクラウド送信は構造的に発生せず、`TranslationGate` は常に `.allow`。
/// - 言語ペア未対応は `TranslationProviderError.languagePairUnsupported`。
/// - モデル未 DL（`.supported`）は `prepareTranslation()` 経由で DL 同意 UI を出す。
///
/// **ライフサイクル（codex レビュー MAJOR-1/2 対応）**: `prepare` は `setLanguages` が返す世代 ID を
/// 取り、`awaitReady` で対応 closure の起動を確認してから成功する（host 未マウントは timeout で
/// fail-closed）。翻訳ジョブは同じ世代で `enqueue` し、teardown 後・世代失効時のゾンビ実行や
/// 継続リークをブリッジ側で防ぐ。
public actor AppleTranslationProvider: TranslationProvider {
    public nonisolated let providerID = "apple"
    public nonisolated let isOnDevice = true

    private let host: any AppleTranslationHosting
    private let availability: any AvailabilityChecking
    /// closure 起動（ready）待ちのタイムアウト。超過で fail-closed（providerError）。
    private let readyTimeout: Duration

    /// 直近の `prepare` が確立した session 世代。`translateStream` の enqueue はこの世代で行う。
    private var activeGeneration: UInt64?

    /// 本番用。常駐ホスト（bridge）と可用性チェッカを注入する。
    public init(bridge: TranslationSessionBridge, availability: any AvailabilityChecking) {
        self.init(host: bridge, availability: availability)
    }

    /// テスト/内部用。ホストをモックに差し替え、実 Translation フレームワーク非依存で検証する。
    init(
        host: any AppleTranslationHosting,
        availability: any AvailabilityChecking,
        readyTimeout: Duration = .seconds(10)
    ) {
        self.host = host
        self.availability = availability
        self.readyTimeout = readyTimeout
    }

    // MARK: TranslationProvider

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        switch await availability.status(from: source, to: target) {
        case .installed:
            let generation = await host.setLanguages(source: source, target: target)
            try await host.awaitReady(generation: generation, timeout: readyTimeout)
            activeGeneration = generation
        case .supported:
            // DL 可能だが未 DL。closure を起こして ready を確認し、DL 同意 UI をアンカー表示する。
            let generation = await host.setLanguages(source: source, target: target)
            try await host.awaitReady(generation: generation, timeout: readyTimeout)
            try await requestModelDownload(generation: generation)
            activeGeneration = generation
        case .unsupported:
            throw TranslationProviderError.languagePairUnsupported(
                source: source.maximalIdentifier,
                target: target.maximalIdentifier
            )
        @unknown default:
            // fail-closed: 未知の対応状況は provider エラー扱い。
            throw TranslationProviderError.providerError("unknown language availability status")
        }
    }

    public func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error> {
        let generation = activeGeneration
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let generation else {
                    continuation.finish(
                        throwing: TranslationProviderError.providerError("translateStream called before prepare")
                    )
                    return
                }
                do {
                    for await input in inputs {
                        try Task.checkCancellation()
                        // 確定セグメントは1件ずつ来る = 実質1要素バッチ。clientIdentifier で
                        // 原文行に対応付ける（応答順序に依存しない）。
                        let request = AppleTranslationRequest(
                            sourceText: input.text,
                            clientID: input.id.uuidString
                        )
                        let responses = try await runBatch([request], generation: generation)
                        for response in responses {
                            // MINOR (a): 1要素バッチなので clientID は入力 id と一致するはず。
                            // 不一致は契約違反として providerError で fail-closed（黙って捨てない）。
                            guard let responseID = UUID(uuidString: response.clientID),
                                  responseID == input.id else {
                                throw TranslationProviderError.providerError(
                                    "clientID mismatch: expected \(input.id.uuidString), got \(response.clientID)"
                                )
                            }
                            continuation.yield(
                                TranslationOutput(
                                    id: input.id,
                                    translatedText: response.targetText,
                                    isConcluded: true,
                                    sourceTime: input.sourceTime
                                )
                            )
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func teardown() async {
        activeGeneration = nil
        await host.endSession()
    }

    // MARK: - ホスト委譲（actor → MainActor、素の値と @Sendable 継続のみ渡す）

    /// ジョブをホストの drain ループへ積み、応答（素の値）を受け取る。
    /// session 自体はホスト closure 内に閉じたまま。teardown/世代失効時はブリッジが
    /// `CancellationError` で継続を確実に解放するため、リークしない（MAJOR-1）。
    private func runBatch(
        _ requests: [AppleTranslationRequest],
        generation: UInt64
    ) async throws -> [AppleTranslationResponse] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[AppleTranslationResponse], Error>) in
            let message = HostMessage.job(
                requests: requests,
                resume: { cont.resume(returning: $0) },
                fail: { cont.resume(throwing: $0) }
            )
            let host = self.host
            Task { @MainActor in host.enqueue(message, generation: generation) }
        }
    }

    /// モデル DL 同意 UI をホストにアンカー表示する（翻訳はしない）。
    private func requestModelDownload(generation: UInt64) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let message = HostMessage.prepareOnly { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
            let host = self.host
            Task { @MainActor in host.enqueue(message, generation: generation) }
        }
    }
}
