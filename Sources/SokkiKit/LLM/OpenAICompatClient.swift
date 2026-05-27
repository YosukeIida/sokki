import Foundation

struct LLMSettings {
    var baseURL: URL
    var apiKey: String?
    var model: String
}

actor OpenAICompatClient {

    private let settings: LLMSettings

    init(settings: LLMSettings) {
        self.settings = settings
    }

    // 話者名推定: 転写テキストから speakerID → 推定名 を返す
    func inferSpeakerNames(
        transcript: String,
        speakerIDs: [String]
    ) async throws -> [String: String] {
        let prompt = """
        以下の会議の文字起こしを読んで、各話者の名前を推定してください。
        話者ID: \(speakerIDs.joined(separator: ", "))

        文字起こし:
        \(transcript)

        JSON形式で回答: {"SPEAKER_00": "推定名", "SPEAKER_01": "推定名"}
        """
        let response = try await chatCompletion(messages: [
            .init(role: "user", content: prompt)
        ])
        return parseSpeakerMapping(response) ?? [:]
    }

    func summarize(transcript: String) async throws -> String {
        try await chatCompletion(messages: [
            .init(role: "system", content: "会議の文字起こしを日本語で要約してください。"),
            .init(role: "user", content: transcript)
        ])
    }

    private func chatCompletion(messages: [ChatMessage]) async throws -> String {
        let url = settings.baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = settings.apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatRequest(model: settings.model, messages: messages)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private func parseSpeakerMapping(_ json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return mapping
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
}

private struct ChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}
