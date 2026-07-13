import Foundation

/// ネットワーク層の注入点。実体は `URLSession.shared.data(for:)` だが、テストでは
/// 実ネットワークにアクセスしないモック transport に差し替える。
public typealias DeepLTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// DeepL REST API（`/v2/translate`）を使う BYO 翻訳プロバイダ。
///
/// Apple Translation が未対応の言語ペアに対するフォールバック先。`TranslationProvider`
/// に適合し、「自分が呼ばれた＝ `TranslationGate` を通過済み」を前提に変換とリソース管理
/// だけを行う（ルーティング/プライバシー判定は持たない）。
///
/// - key 取得: `APIKeyProviding` 経由の単一アクセス点（TASK-23 の Keychain 実装に差し替え予定）。
/// - Free/Pro 判定: DeepL の慣習どおり、キーの末尾が `:fx` なら Free エンドポイント
///   （`api-free.deepl.com`）、それ以外は Pro エンドポイント（`api.deepl.com`）を使う。
/// - レート制限: 429 は 1 回だけ待機してリトライする。それ以外の HTTP エラーは
///   `TranslationProviderError` に写像する（401/403 は key 起因とみなし `.missingAPIKey`）。
public actor DeepLTranslationProvider: TranslationProvider {
    public nonisolated let providerID = TranslationProviderKind.deepL.rawValue
    public nonisolated let isOnDevice = false

    private let keyProvider: any APIKeyProviding
    private let transport: DeepLTransport
    private let retryDelay: Duration
    private let sleeper: @Sendable (Duration) async throws -> Void

    private var apiKey: String?
    private var source: Locale.Language?
    private var target: Locale.Language?

    /// - Parameters:
    ///   - keyProvider: BYO キーの実体取得（単一アクセス点）。
    ///   - transport: HTTP 送受信の注入点。既定は `URLSession.shared.data(for:)`。
    ///   - retryDelay: 429 時の待機時間（`Retry-After` ヘッダがあればそちらを優先）。
    ///   - sleeper: 待機処理の注入点。テストでは即時完了する no-op に差し替える。
    public init(
        keyProvider: any APIKeyProviding,
        transport: @escaping DeepLTransport = { try await URLSession.shared.data(for: $0) },
        retryDelay: Duration = .milliseconds(500),
        sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.keyProvider = keyProvider
        self.transport = transport
        self.retryDelay = retryDelay
        self.sleeper = sleeper
    }

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        guard let key = await keyProvider.apiKey(for: providerID), !key.isEmpty else {
            throw TranslationProviderError.missingAPIKey
        }
        self.apiKey = key
        self.source = source
        self.target = target
    }

    public func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await input in inputs {
                        if Task.isCancelled { break }
                        let output = try await self.translateOne(input)
                        continuation.yield(output)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // 出力ストリームの消費側キャンセル or finish で、進行中の HTTP リクエストへ
            // キャンセルを伝播させる（`transport` が cooperative cancellation に対応する前提。
            // 実体の `URLSession.data(for:)` はこれに対応する）。
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func teardown() async {
        // 専有 URLSession/socket は持たない（`transport` は共有インスタンス想定）ため、
        // 保持している認証状態を破棄するだけで冪等にクローズできる。
        apiKey = nil
        source = nil
        target = nil
    }

    private func translateOne(_ input: TranslationInput) async throws -> TranslationOutput {
        guard let key = apiKey, let source, let target else {
            throw TranslationProviderError.missingAPIKey
        }
        let translatedText = try await performRequest(
            text: input.text, key: key, source: source, target: target, allowRetry: true
        )
        return TranslationOutput(
            id: input.id, translatedText: translatedText,
            isConcluded: true, sourceTime: input.sourceTime
        )
    }

    private func performRequest(
        text: String, key: String, source: Locale.Language, target: Locale.Language, allowRetry: Bool
    ) async throws -> String {
        let request: URLRequest
        do {
            request = try Self.makeRequest(text: text, key: key, source: source, target: target)
        } catch {
            throw TranslationProviderError.providerError(
                "failed to encode DeepL request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            if error is CancellationError { throw error }
            throw TranslationProviderError.connectionFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationProviderError.connectionFailed("DeepL response is not HTTP")
        }

        switch http.statusCode {
        case 200:
            do {
                return try Self.parseTranslation(data)
            } catch let error as TranslationProviderError {
                throw error
            } catch {
                throw TranslationProviderError.providerError(
                    "failed to decode DeepL response: \(error.localizedDescription)")
            }
        case 401, 403:
            // DeepL は無効/失効キーで 403 を返す（401 も防御的に同様に扱う）。
            throw TranslationProviderError.missingAPIKey
        case 429 where allowRetry:
            try await sleeper(Self.retryDelay(from: http, default: retryDelay))
            return try await performRequest(
                text: text, key: key, source: source, target: target, allowRetry: false)
        case 456:
            // DeepL 固有: Free の月間文字数上限 or Pro の Cost Control 上限到達（quota exceeded）。
            // 通信失敗ではないため `.connectionFailed` に寄せず、リトライしても解消しない
            // エラーとして区別できるよう `.providerError` に写像する（キー文字列は含めない）。
            throw TranslationProviderError.providerError("DeepL quota exceeded (HTTP 456)")
        default:
            throw TranslationProviderError.connectionFailed("DeepL HTTP \(http.statusCode)")
        }
    }

    private static func retryDelay(from response: HTTPURLResponse, default fallback: Duration) -> Duration {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(value), seconds > 0
        else { return fallback }
        return .seconds(seconds)
    }

    private static func baseURL(for apiKey: String) -> URL {
        // DeepL の慣習: Free プランのキーは末尾が ":fx"。
        apiKey.hasSuffix(":fx")
            ? URL(string: "https://api-free.deepl.com/v2/translate")!
            : URL(string: "https://api.deepl.com/v2/translate")!
    }

    private static func makeRequest(
        text: String, key: String, source: Locale.Language, target: Locale.Language
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL(for: key))
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = DeepLRequestBody(
            text: [text],
            sourceLang: DeepLLanguageMapping.code(for: source, role: .source),
            targetLang: DeepLLanguageMapping.code(for: target, role: .target)
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func parseTranslation(_ data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(DeepLResponseBody.self, from: data)
        guard let first = decoded.translations.first else {
            throw TranslationProviderError.providerError("DeepL response has no translations")
        }
        return first.text
    }
}

// MARK: - REST payload

private struct DeepLRequestBody: Encodable {
    let text: [String]
    let sourceLang: String?
    let targetLang: String

    enum CodingKeys: String, CodingKey {
        case text
        case sourceLang = "source_lang"
        case targetLang = "target_lang"
    }
}

private struct DeepLResponseBody: Decodable {
    struct Translation: Decodable {
        let text: String
        let detectedSourceLanguage: String?

        enum CodingKeys: String, CodingKey {
            case text
            case detectedSourceLanguage = "detected_source_language"
        }
    }
    let translations: [Translation]
}
