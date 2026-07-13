import Foundation
@testable import SokkiKit

/// 固定キーを返す注入可能な `APIKeyProviding`。空文字/`nil` を渡すと未設定を模擬できる。
struct StubAPIKeyProvider: APIKeyProviding {
    let key: String?

    init(key: String? = "test-key:fx") { self.key = key }

    func apiKey(for providerID: String) async -> String? { key }
}

/// HTTP レスポンスをスクリプトで返す注入可能な transport。
///
/// `responses` を先頭から順に1回ずつ消費する。呼び出し回数が `responses` を超えたら
/// 最後の応答を使い回す。呼び出しごとの `URLRequest` を `recordedRequests` に記録するため、
/// ヘッダ/ボディの検証にも使える。
actor ScriptedDeepLTransport {
    enum Step {
        case success(text: String)
        case status(Int, headers: [String: String] = [:])
        case failure(Error)
    }

    private var steps: [Step]
    private(set) var recordedRequests: [URLRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func callAsFunction(_ request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        let step = steps.isEmpty ? .status(200) : steps.removeFirst()
        let url = request.url ?? URL(string: "https://api-free.deepl.com/v2/translate")!

        switch step {
        case .success(let text):
            let body = """
            {"translations":[{"detected_source_language":"JA","text":"\(text)"}]}
            """
            let data = Data(body.utf8)
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        case .status(let code, let headers):
            let response = HTTPURLResponse(
                url: url, statusCode: code, httpVersion: nil, headerFields: headers)!
            return (Data(), response)
        case .failure(let error):
            throw error
        }
    }

    nonisolated var transport: DeepLTransport {
        { [self] request in try await self.callAsFunction(request) }
    }
}

/// キャンセルされるまで一切応答を返さない transport。teardown/消費側キャンセルによる
/// in-flight リクエストへの Task cancellation 伝播を検証するために使う。
///
/// `withTaskCancellationHandler` の `onCancel` はハンドラが呼ばれるだけで continuation を
/// 自動解放しないため、明示的に `resume(throwing: CancellationError())` する。
actor HangingDeepLTransport {
    private(set) var callCount = 0
    private(set) var wasCancelled = false
    private var pending: CheckedContinuation<(Data, URLResponse), Error>?

    nonisolated var transport: DeepLTransport {
        { [self] request in try await self.hang(request) }
    }

    private func hang(_ request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (k: CheckedContinuation<(Data, URLResponse), Error>) in
                self.pending = k
            }
        } onCancel: {
            Task { await self.cancelPending() }
        }
    }

    private func cancelPending() {
        wasCancelled = true
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
}
