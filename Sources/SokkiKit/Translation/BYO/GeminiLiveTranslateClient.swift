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

    public static func setupMessage(model: String, source: String, target: String) throws -> String {
        let object: [String: Any] = ["setup": [
            "model": model,
            "generationConfig": ["responseModalities": ["AUDIO"]],
            "systemInstruction": ["parts": [["text": "Translate spoken \(source) into \(target)."]]],
            "inputAudioTranscription": [:],
            "outputAudioTranscription": [:]
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
        model: String = "models/gemini-2.0-flash-live-001"
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
        self.source = source.minimalIdentifier
        self.target = target.minimalIdentifier
        do {
            let socket = try await connector.connect(to: url)
            connection = socket
            try await socket.send(text: GeminiLiveMessageCodec.setupMessage(
                model: model, source: self.source, target: self.target
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
                    while !Task.isCancelled {
                        let outputs = try GeminiLiveMessageCodec.outputs(
                            from: try await socket.receiveText(), id: turnID, sourceTime: startedAt
                        )
                        for output in outputs {
                            continuation.yield(output)
                        }
                        if outputs.contains(where: \.isConcluded) {
                            concluded = true
                            break
                        }
                    }
                    // Only flush the send side when the turn concluded normally: real Gemini
                    // Live only reports turnComplete after consuming the client's
                    // audioStreamEnd, so this resolves promptly. On the cancellation exit path
                    // `samples` may still be open, and `sendTask` isn't cancelled until the
                    // `defer` above runs after this function returns — awaiting it here would
                    // deadlock.
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
        return .connectionFailed(String(describing: error))
    }
}
