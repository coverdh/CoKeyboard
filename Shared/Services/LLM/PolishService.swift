import Foundation

final class PolishService {
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func polish(text: String, vocabulary: [VocabularyItem] = []) async -> PolishResult {
        guard NetworkMonitor.shared.isConnected else {
            return PolishResult(text: text, polishTokens: 0, wasPolished: false)
        }

        guard let client = LLMClientFactory.create(settings: settings) else {
            return PolishResult(text: text, polishTokens: 0, wasPolished: false)
        }

        let systemPrompt = buildSystemPrompt(vocabulary: vocabulary)

        for attempt in 0...AppConstants.llmMaxRetries {
            do {
                let response = try await client.complete(
                    systemPrompt: systemPrompt,
                    userMessage: text
                )
                return PolishResult(
                    text: response.text,
                    polishTokens: response.promptTokens + response.completionTokens,
                    wasPolished: true,
                    provider: settings.llmProvider
                )
            } catch {
                if attempt == AppConstants.llmMaxRetries {
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }

        return PolishResult(text: text, polishTokens: 0, wasPolished: false)
    }

    private func buildSystemPrompt(vocabulary: [VocabularyItem]) -> String {
        var prompt = """
        You are a text polishing assistant. Your job is to clean up and improve speech-to-text output.
        Fix grammar, punctuation, and make the text more natural while preserving the original meaning.
        Only output the polished text, nothing else.
        """

        if !vocabulary.isEmpty {
            let terms = vocabulary.map { item in
                if let context = item.context, !context.isEmpty {
                    return "- \(item.term): \(context)"
                }
                return "- \(item.term)"
            }.joined(separator: "\n")
            prompt += "\n\nCustom vocabulary (use these terms when appropriate):\n\(terms)"
        }

        return prompt
    }
}

struct PolishResult: Sendable {
    let text: String
    let polishTokens: Int
    let wasPolished: Bool
    var provider: String?
}
