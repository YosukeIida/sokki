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
public actor AppleTranslationProvider: TranslationProvider {
    public nonisolated let providerID = "apple"
    public nonisolated let isOnDevice = true

    private let host: any AppleTranslationHosting
    private let availability: any AvailabilityChecking

    /// 本番用。常駐ホスト（bridge）と可用性チェッカを注入する。
    public init(bridge: TranslationSessionBridge, availability: any AvailabilityChecking) {
        self.init(host: bridge, availability: availability)
    }

    /// テスト/内部用。ホストをモックに差し替え、実 Translation フレームワーク非依存で検証する。
    init(host: any AppleTranslationHosting, availability: any AvailabilityChecking) {
        self.host = host
        self.availability = availability
    }

    // MARK: TranslationProvider

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        switch await availability.status(from: source, to: target) {
        case .installed:
            await host.setLanguages(source: source, target: target)
        case .supported:
            // DL 可能だが未 DL。言語を設定して closure を起こし、DL 同意 UI をアンカー表示する。
            await host.setLanguages(source: source, target: target)
            try await requestModelDownload()
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
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await input in inputs {
                        try Task.checkCancellation()
                        // 確定セグメントは1件ずつ来る = 実質1要素バッチ。clientIdentifier で
                        // 原文行に対応付ける（応答順序に依存しない）。
                        let request = AppleTranslationRequest(
                            sourceText: input.text,
                            clientID: input.id.uuidString
                        )
                        let responses = try await runBatch([request])
                        for response in responses {
                            let id = UUID(uuidString: response.clientID) ?? input.id
                            continuation.yield(
                                TranslationOutput(
                                    id: id,
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
        await host.clearConfiguration()
    }

    // MARK: - ホスト委譲（actor → MainActor、素の値と @Sendable 継続のみ渡す）

    /// ジョブをホストの drain ループへ積み、応答（素の値）を受け取る。
    /// session 自体はホスト closure 内に閉じたまま。
    ///
    /// > 未検証（実機 PoC）: in-flight ジョブ中に `teardown()`（`clearConfiguration`）が走ると、
    /// > closure が破棄されジョブが drain されず、この継続が再開されない可能性がある
    /// > （`docs/translation-architecture.md` §14.6）。
    private func runBatch(_ requests: [AppleTranslationRequest]) async throws -> [AppleTranslationResponse] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[AppleTranslationResponse], Error>) in
            let message = HostMessage.job(
                requests: requests,
                resume: { cont.resume(returning: $0) },
                fail: { cont.resume(throwing: $0) }
            )
            let host = self.host
            Task { @MainActor in host.enqueue(message) }
        }
    }

    /// モデル DL 同意 UI をホストにアンカー表示する（翻訳はしない）。
    private func requestModelDownload() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let message = HostMessage.prepareOnly { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
            let host = self.host
            Task { @MainActor in host.enqueue(message) }
        }
    }
}
