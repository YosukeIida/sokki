import Foundation
import Testing
@testable import SokkiKit

@Suite("Gemini Live 翻訳 client（実験的）")
struct GeminiLiveTranslateClientTests {
    @Test("Float32 を clamping して Int16 little-endian PCM に変換する")
    func pcmConversion() {
        let data = PCMConverter.int16LittleEndianData(from: [-2, -1, 0, 0.5, 1, 2])
        #expect(Array(data) == [
            0x00, 0x80, 0x00, 0x80, 0x00, 0x00,
            0x00, 0x40, 0xff, 0x7f, 0xff, 0x7f,
        ])
    }

    @Test("setup は model・両 transcription・audio modality を含む")
    func setupShape() throws {
        let message = try GeminiLiveMessageCodec.setupMessage(
            model: "models/test", source: "ja", target: "en"
        )
        let root = try #require(try json(message))
        let setup = try #require(root["setup"] as? [String: Any])
        #expect(setup["model"] as? String == "models/test")
        #expect(setup["inputAudioTranscription"] is [String: Any])
        #expect(setup["outputAudioTranscription"] is [String: Any])
        let generation = try #require(setup["generationConfig"] as? [String: Any])
        #expect(generation["responseModalities"] as? [String] == ["AUDIO"])
        #expect(try GeminiLiveMessageCodec.isSetupComplete(#"{"setupComplete":{}}"#))
    }

    @Test("serverContent の原文・訳文 transcription を取り出す")
    func transcriptionMapping() throws {
        let message = #"{"serverContent":{"inputTranscription":{"text":"こんにちは"},"outputTranscription":{"text":"Hello"},"turnComplete":true}}"#
        let values = try GeminiLiveMessageCodec.transcriptions(from: message)
        #expect(values == [
            .init(kind: .input, text: "こんにちは", isTurnComplete: true),
            .init(kind: .output, text: "Hello", isTurnComplete: true),
        ])
        let id = UUID()
        let outputs = try GeminiLiveMessageCodec.outputs(from: message, id: id, sourceTime: 1.25)
        #expect(outputs == [
            .init(id: id, translatedText: "こんにちは", isConcluded: false, sourceTime: 1.25),
            .init(id: id, translatedText: "Hello", isConcluded: true, sourceTime: 1.25),
        ])
    }

    @Test("prepare は key を query にのみ付け setup を送り、teardown は close する")
    func prepareAndTeardown() async throws {
        let socket = MockWebSocket()
        let connector = MockConnector(socket: socket)
        let client = GeminiLiveTranslateClient(
            keyProvider: StubKeyProvider(value: "secret-key"), connector: connector,
            endpoint: URL(string: "wss://example.invalid/live")!, model: "models/test"
        )
        try await client.prepare(
            source: Locale.Language(identifier: "ja"),
            target: Locale.Language(identifier: "en")
        )
        let url = try #require(await connector.connectedURL)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "key", value: "secret-key")
        ])
        let sentCount = await socket.sentMessages.count
        #expect(sentCount == 1)

        await client.teardown()
        await client.teardown()
        let closeCount = await socket.closeCount
        #expect(closeCount == 1)
    }

    @Test("キー無しと transport error を TranslationProviderError に写像する")
    func errorMapping() async {
        let missing = GeminiLiveTranslateClient(
            keyProvider: StubKeyProvider(value: nil), connector: MockConnector(socket: MockWebSocket())
        )
        await #expect(throws: TranslationProviderError.missingAPIKey) {
            try await missing.prepare(
                source: Locale.Language(identifier: "ja"),
                target: Locale.Language(identifier: "en")
            )
        }
        #expect(GeminiLiveTranslateClient.mapError(MockFailure.broken) == .connectionFailed("broken"))
    }

    @Test("音声終了を通知し、確定訳で output stream と socket を閉じる")
    func audioLifecycle() async throws {
        let socket = MockWebSocket(responses: [
            #"{"setupComplete":{}}"#,
            #"{"serverContent":{"outputTranscription":{"text":"Hello"},"turnComplete":true}}"#,
        ])
        let client = GeminiLiveTranslateClient(
            keyProvider: StubKeyProvider(value: "test-key"), connector: MockConnector(socket: socket)
        )
        try await client.prepare(
            source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "en")
        )
        let input = AsyncStream<[Float]> { continuation in
            continuation.yield([0, 1])
            continuation.finish()
        }
        var outputs: [TranslationOutput] = []
        for try await output in await client.translateAudioStream(input) { outputs.append(output) }

        #expect(outputs.map(\.translatedText) == ["Hello"])
        #expect(outputs.allSatisfy { $0.isConcluded })
        let messages = await socket.sentMessages
        #expect(messages.count == 3) // setup, PCM, audioStreamEnd
        #expect(messages.last?.contains("audioStreamEnd") == true)
        let closes = await socket.closeCount
        #expect(closes == 1)
    }

    private func json(_ string: String) throws -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private struct StubKeyProvider: GeminiAPIKeyProviding {
    let value: String?
    func apiKey() async throws -> String? { value }
}

private actor MockConnector: WebSocketConnecting {
    let socket: MockWebSocket
    private(set) var connectedURL: URL?

    init(socket: MockWebSocket) { self.socket = socket }
    func connect(to url: URL) async throws -> any WebSocketConnection {
        connectedURL = url
        return socket
    }
}

private actor MockWebSocket: WebSocketConnection {
    private(set) var sentMessages: [String] = []
    private(set) var closeCount = 0
    private var responses: [String]

    init(responses: [String] = [#"{"setupComplete":{}}"#]) { self.responses = responses }

    func send(text: String) { sentMessages.append(text) }
    func receiveText() async throws -> String {
        guard !responses.isEmpty else { throw MockFailure.broken }
        return responses.removeFirst()
    }
    func close() { closeCount += 1 }
}

private enum MockFailure: Error, CustomStringConvertible {
    case broken
    var description: String { "broken" }
}
