import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    var llmProvider: String {
        didSet {
            defaults.set(llmProvider, forKey: "llmProvider")
            // Reset to provider defaults when switching
            if oldValue != llmProvider {
                applyProviderDefaults()
            }
        }
    }
    var llmAPIKey: String {
        didSet { defaults.set(llmAPIKey, forKey: "llmAPIKey") }
    }
    var llmBaseURL: String {
        didSet { defaults.set(llmBaseURL, forKey: "llmBaseURL") }
    }
    var llmModel: String {
        didSet { defaults.set(llmModel, forKey: "llmModel") }
    }
    var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: "targetLanguage") }
    }
    
    // 语音识别主语言设置: "auto" | "zh" | "en" | "ja" | "ko" | ...
    var speechRecognitionLanguage: String {
        didSet { defaults.set(speechRecognitionLanguage, forKey: "speechRecognitionLanguage") }
    }
    
    // 语音识别辅助语言: nil | "en" | "zh" | ... (当主语言识别失败时尝试)
    var speechSecondaryLanguage: String? {
        didSet { defaults.set(speechSecondaryLanguage, forKey: "speechSecondaryLanguage") }
    }
    
    var voiceBackgroundDuration: Int {
        didSet { defaults.set(voiceBackgroundDuration, forKey: "voiceBackgroundDuration") }
    }

    // Provider-specific defaults
    static let providerDefaults: [String: (baseURL: String, model: String)] = [
        "openai": ("https://api.openai.com/v1", "gpt-4o-mini"),
        "bailian": ("https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus"),
        "custom": ("", "")
    ]

    // Effective values (use defaults if not customized)
    var effectiveBaseURL: String {
        if llmProvider == "bailian" {
            return Self.providerDefaults["bailian"]!.baseURL
        }
        return llmBaseURL
    }

    var effectiveModel: String {
        if llmProvider == "bailian" && llmModel.isEmpty {
            return Self.providerDefaults["bailian"]!.model
        }
        return llmModel
    }

    private init() {
        let suiteName = AppConstants.appGroupID
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults with suite: \(suiteName)")
        }
        self.defaults = defaults

        self.llmProvider = defaults.string(forKey: "llmProvider") ?? "openai"
        self.llmAPIKey = defaults.string(forKey: "llmAPIKey") ?? ""
        self.llmBaseURL = defaults.string(forKey: "llmBaseURL") ?? Self.providerDefaults["openai"]!.baseURL
        self.llmModel = defaults.string(forKey: "llmModel") ?? Self.providerDefaults["openai"]!.model
        self.targetLanguage = defaults.string(forKey: "targetLanguage") ?? AppConstants.defaultTargetLanguage
        self.speechRecognitionLanguage = defaults.string(forKey: "speechRecognitionLanguage") ?? "zh"
        self.speechSecondaryLanguage = defaults.string(forKey: "speechSecondaryLanguage") ?? "en"
        let bgDur = defaults.integer(forKey: "voiceBackgroundDuration")
        self.voiceBackgroundDuration = bgDur > 0 ? bgDur : AppConstants.defaultVoiceBackgroundDuration
    }

    func reload() {
        llmProvider = defaults.string(forKey: "llmProvider") ?? "openai"
        llmAPIKey = defaults.string(forKey: "llmAPIKey") ?? ""
        llmBaseURL = defaults.string(forKey: "llmBaseURL") ?? Self.providerDefaults["openai"]!.baseURL
        llmModel = defaults.string(forKey: "llmModel") ?? Self.providerDefaults["openai"]!.model
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? AppConstants.defaultTargetLanguage
        speechRecognitionLanguage = defaults.string(forKey: "speechRecognitionLanguage") ?? "zh"
        speechSecondaryLanguage = defaults.string(forKey: "speechSecondaryLanguage") ?? "en"
        let bgDur = defaults.integer(forKey: "voiceBackgroundDuration")
        voiceBackgroundDuration = bgDur > 0 ? bgDur : AppConstants.defaultVoiceBackgroundDuration
    }

    private func applyProviderDefaults() {
        guard let providerDefault = Self.providerDefaults[llmProvider] else { return }
        if llmProvider != "custom" {
            llmBaseURL = providerDefault.baseURL
            llmModel = providerDefault.model
        }
    }
}
