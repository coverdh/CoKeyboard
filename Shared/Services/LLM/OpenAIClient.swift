import Foundation

struct OpenAIClient: LLMClient {
    let apiKey: String
    let baseURL: String
    let model: String

    func complete(systemPrompt: String, userMessage: String) async throws -> LLMResponse {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AppConstants.llmTimeoutSeconds

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        var promptTokens = 0
        var completionTokens = 0
        if let usage = json["usage"] as? [String: Any] {
            promptTokens = usage["prompt_tokens"] as? Int ?? 0
            completionTokens = usage["completion_tokens"] as? Int ?? 0
        }

        return LLMResponse(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }
}
