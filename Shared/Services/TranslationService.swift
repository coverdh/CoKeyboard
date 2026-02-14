import Foundation

final class TranslationService {
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func translate(text: String) async -> String {
        guard !text.isEmpty else { return text }

        guard NetworkMonitor.shared.isConnected,
              let client = LLMClientFactory.create(settings: settings) else {
            return text
        }

        let targetLang = settings.targetLanguage
        let systemPrompt = """
        You are a translator. Translate the following text to \(targetLang).
        Only output the translated text, nothing else.
        """

        do {
            let response = try await client.complete(
                systemPrompt: systemPrompt,
                userMessage: text
            )
            return response.text
        } catch {
            return text
        }
    }
}
