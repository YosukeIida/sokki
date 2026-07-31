import Foundation

public protocol GeminiAPIKeyProviding: Sendable {
    func apiKey() async throws -> String?
}

public protocol WebSocketConnection: Actor {
    func send(text: String) async throws
    func receiveText() async throws -> String
    func close() async
}

public protocol WebSocketConnecting: Sendable {
    func connect(to url: URL) async throws -> any WebSocketConnection
}

public struct URLSessionWebSocketConnector: WebSocketConnecting {
    public init() {}

    public func connect(to url: URL) async throws -> any WebSocketConnection {
        URLSessionWebSocketConnection(url: url)
    }
}

private actor URLSessionWebSocketConnection: WebSocketConnection {
    private let task: URLSessionWebSocketTask
    private var isClosed = false

    init(url: URL) {
        task = URLSession.shared.webSocketTask(with: url)
        task.resume()
    }

    func send(text: String) async throws { try await task.send(.string(text)) }

    func receiveText() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw TranslationProviderError.providerError("Gemini Live returned non-UTF-8 data")
            }
            return text
        @unknown default:
            throw TranslationProviderError.providerError("Gemini Live returned an unknown frame")
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        task.cancel(with: .normalClosure, reason: nil)
    }
}

public enum GeminiLiveMessageCodec {
    public enum TranscriptionKind: Sendable, Equatable { case input, output }
    public struct Transcription: Sendable, Equatable {
        public let kind: TranscriptionKind
        public let text: String
        public let isTurnComplete: Bool
    }

    /// `targetLanguageCode` は BCP-47（例: "en"）。Gemini Live Translate は source を
    /// auto-detect するため setup には含めない（`translationConfig` に `sourceLanguageCode` は無い）。
    /// フィールド構成は Live Translate 専用モデルの `generationConfig.translationConfig` 準拠
    /// （`systemInstruction` によるプロンプト誘導ではない）。
    public static func setupMessage(model: String, targetLanguageCode: String) throws -> String {
        let object: [String: Any] = ["setup": [
            "model": model,
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "inputAudioTranscription": [:],
                "outputAudioTranscription": [:],
                "translationConfig": ["targetLanguageCode": targetLanguageCode]
            ]
        ]]
        return try jsonString(object)
    }

    public static func audioMessage(_ pcm: Data) throws -> String {
        try jsonString(["realtimeInput": ["audio": [
            "mimeType": "audio/pcm;rate=16000", "data": pcm.base64EncodedString()
        ]]])
    }

    public static func audioStreamEndMessage() throws -> String {
        try jsonString(["realtimeInput": ["audioStreamEnd": true]])
    }

    public static func isSetupComplete(_ text: String) throws -> Bool {
        guard let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return root["setupComplete"] is [String: Any]
    }

    /// serverContent の `turnComplete` を、transcription の有無に関係なく判定する。
    /// 公式ドキュメント上、transcription は他の server message と独立に送信され順序保証が無いため、
    /// `turnComplete` だけが単独フレームで届くケースがある（`transcriptions(from:)` はそのフレームでは
    /// 空配列を返す）。呼び出し側はこれを別途チェックし、確定応答の取り逃しを防ぐ必要がある。
    public static func isTurnComplete(_ text: String) throws -> Bool {
        guard let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["serverContent"] as? [String: Any] else { return false }
        return content["turnComplete"] as? Bool ?? false
    }

    public static func transcriptions(from text: String) throws -> [Transcription] {
        guard let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["serverContent"] as? [String: Any] else { return [] }
        let complete = content["turnComplete"] as? Bool ?? false
        var result: [Transcription] = []
        if let value = (content["inputTranscription"] as? [String: Any])?["text"] as? String,
           !value.isEmpty { result.append(.init(kind: .input, text: value, isTurnComplete: complete)) }
        if let value = (content["outputTranscription"] as? [String: Any])?["text"] as? String,
           !value.isEmpty { result.append(.init(kind: .output, text: value, isTurnComplete: complete)) }
        return result
    }

    public static func outputs(
        from text: String,
        id: UUID,
        sourceTime: TimeInterval
    ) throws -> [TranslationOutput] {
        try transcriptions(from: text).map { item in
            TranslationOutput(
                id: id,
                translatedText: item.text,
                isConcluded: item.kind == .output && item.isTurnComplete,
                sourceTime: sourceTime
            )
        }
    }

    private static func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let value = String(data: data, encoding: .utf8) else {
            throw TranslationProviderError.providerError("Failed to encode Gemini Live message")
        }
        return value
    }
}

/// Experimental/preview BYO-key client for Gemini Live v1alpha.
public actor GeminiLiveTranslateClient: AudioTranslationProviding {
    public nonisolated let providerID = TranslationProviderKind.geminiLive.rawValue
    public nonisolated let isOnDevice = false

    private let keyProvider: any GeminiAPIKeyProviding
    private let connector: any WebSocketConnecting
    private let endpoint: URL
    private let model: String
    private var connection: (any WebSocketConnection)?
    private var source = ""
    private var target = ""
    private var sendError: TranslationProviderError?

    public init(
        keyProvider: any GeminiAPIKeyProviding,
        connector: any WebSocketConnecting = URLSessionWebSocketConnector(),
        endpoint: URL = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent")!,
        // `gemini-2.0-flash-live-001` は 2025-12-09 に shutdown 済みで、docs/superintern-feature-plan.md /
        // docs/realtime-translation-research.md が定める Live Translate 専用モデルとも異なる。
        model: String = "models/gemini-3.5-live-translate-preview"
    ) {
        self.keyProvider = keyProvider
        self.connector = connector
        self.endpoint = endpoint
        self.model = model
    }

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        await teardown()
        let key: String
        do {
            guard let value = try await keyProvider.apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { throw TranslationProviderError.missingAPIKey }
            key = value
        } catch {
            throw Self.mapError(error)
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TranslationProviderError.connectionFailed("Invalid Gemini Live endpoint")
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: key)]
        guard let url = components.url else {
            throw TranslationProviderError.connectionFailed("Invalid Gemini Live endpoint")
        }
        // source は Live Translate では auto-detect のため setup ペイロードには使わない
        // （`prepare(source:target:)` は protocol 契約上必須のパラメータとして保持するのみ）。
        self.source = source.minimalIdentifier
        self.target = target.minimalIdentifier
        do {
            let socket = try await connector.connect(to: url)
            connection = socket
            try await socket.send(text: GeminiLiveMessageCodec.setupMessage(
                model: model, targetLanguageCode: self.target
            ))
            guard try GeminiLiveMessageCodec.isSetupComplete(try await socket.receiveText()) else {
                throw TranslationProviderError.connectionFailed("Gemini Live setup was not acknowledged")
            }
        } catch {
            await teardown()
            throw Self.mapError(error)
        }
    }

    public func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error> {
        AsyncThrowingStream { $0.finish(throwing: TranslationProviderError.providerError(
            "Gemini Live requires the audio translation extension"
        )) }
    }

    public func translateAudioStream(
        _ samples: AsyncStream<[Float]>
    ) -> AsyncThrowingStream<TranslationOutput, Error> {
        let turnID = UUID()
        let startedAt = Date().timeIntervalSince1970
        sendError = nil
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let socket = self.connection else {
                        throw TranslationProviderError.connectionFailed("Gemini Live is not prepared")
                    }
                    let sendTask = Task {
                        do {
                            for await chunk in samples {
                                try Task.checkCancellation()
                                let message = try GeminiLiveMessageCodec.audioMessage(
                                    PCMConverter.int16LittleEndianData(from: chunk)
                                )
                                try await socket.send(text: message)
                            }
                            try await socket.send(text: GeminiLiveMessageCodec.audioStreamEndMessage())
                        } catch is CancellationError {
                            // Parent termination owns the close.
                        } catch {
                            // Closing wakes a blocked receive so its error can terminate the output stream.
                            await self.recordSendError(error)
                            await self.teardown()
                        }
                    }
                    defer { sendTask.cancel() }
                    var concluded = false
                    var lastOutputText = ""
                    while !Task.isCancelled {
                        let raw = try await socket.receiveText()
                        // transcription (inputTranscription/outputTranscription) is sent by the
                        // server independently of turnComplete with no ordering guarantee, so a
                        // turnComplete frame can arrive with no transcription payload at all.
                        // Track the most recently seen output-language text separately from the
                        // per-frame turnComplete flag, and only fall back to synthesizing the
                        // concluded output below when this frame didn't already carry one —
                        // otherwise the receive loop would wait forever for a combined
                        // transcription+turnComplete frame that never arrives.
                        var yieldedConcludedThisFrame = false
                        for item in try GeminiLiveMessageCodec.transcriptions(from: raw) {
                            if item.kind == .output { lastOutputText = item.text }
                            let isConcludedItem = item.kind == .output && item.isTurnComplete
                            continuation.yield(TranslationOutput(
                                id: turnID, translatedText: item.text,
                                isConcluded: isConcludedItem, sourceTime: startedAt
                            ))
                            if isConcludedItem { yieldedConcludedThisFrame = true }
                        }
                        if try GeminiLiveMessageCodec.isTurnComplete(raw) {
                            if !yieldedConcludedThisFrame {
                                continuation.yield(TranslationOutput(
                                    id: turnID, translatedText: lastOutputText,
                                    isConcluded: true, sourceTime: startedAt
                                ))
                            }
                            concluded = true
                            break
                        }
                    }
                    // NOTE: this method surfaces exactly one turn per call (single `turnID`).
                    // With Gemini Live's default automatic VAD, `turnComplete` fires on a natural
                    // pause in speech, not only after the client sends `audioStreamEnd` — so for
                    // a long-lived `samples` stream (e.g. a whole meeting) this only reports the
                    // first turn and then blocks below until `samples` itself finishes. Continuous
                    // multi-turn handling belongs to the follow-up audio-wiring task, which will
                    // need to keep looping across turns while `samples` stays open instead of
                    // returning after the first `concluded`.
                    if concluded {
                        await sendTask.value
                    }
                    await self.teardown()
                    continuation.finish()
                } catch is CancellationError {
                    await self.teardown()
                    continuation.finish()
                } catch {
                    let mapped = await self.takeSendError() ?? Self.mapError(error)
                    await self.teardown()
                    continuation.finish(throwing: mapped)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func teardown() async {
        let active = connection
        connection = nil
        await active?.close() // close first: error-path self-cancellation must not strand the socket.
    }

    private func recordSendError(_ error: Error) { sendError = Self.mapError(error) }
    private func takeSendError() -> TranslationProviderError? {
        defer { sendError = nil }
        return sendError
    }

    public nonisolated static func mapError(_ error: Error) -> TranslationProviderError {
        if let mapped = error as? TranslationProviderError { return mapped }
        return .connectionFailed(redactingAPIKey(String(describing: error)))
    }

    /// Transport errors (e.g. `URLError`/`NSError`) can carry the failing URL — including the
    /// BYO key passed as the `key` query parameter — inside their `userInfo`, which
    /// `String(describing:)` prints verbatim. Redact `key=...` query values so the raw key
    /// never reaches `TranslationProviderError.connectionFailed`'s message (UI alerts / logs).
    private nonisolated static func redactingAPIKey(_ description: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "key=[^&\\s\"'}]+", options: [.caseInsensitive])
        else { return description }
        let range = NSRange(description.startIndex..., in: description)
        return regex.stringByReplacingMatches(in: description, range: range, withTemplate: "key=<redacted>")
    }
}
