import Foundation

protocol LLMClient: Sendable {
    func complete(systemPrompt: String, userMessage: String) async throws -> LLMResponse
}

struct LLMResponse: Sendable {
    let text: String
    let promptTokens: Int
    let completionTokens: Int
}

enum LLMError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Invalid API key"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .invalidResponse: return "Invalid response from server"
        case .serverError(let msg): return "Server error: \(msg)"
        }
    }
}

enum LLMClientFactory {
    static func create(settings: AppSettings) -> (any LLMClient)? {
        guard !settings.llmAPIKey.isEmpty else { return nil }
        return OpenAIClient(
            apiKey: settings.llmAPIKey,
            baseURL: settings.effectiveBaseURL,
            model: settings.effectiveModel
        )
    }
}
