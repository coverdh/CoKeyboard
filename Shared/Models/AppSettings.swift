import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // MARK: - Transcription Engine
    var transcriptionEngine: String {
        didSet {
            defaults.set(transcriptionEngine, forKey: "transcriptionEngine")
            // 切换引擎后清理旧引擎资源
            if oldValue != transcriptionEngine {
                unloadTranscriptionEngine()
            }
        }
    }
    
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
    
    // 语音识别语言设置: "auto" | "zh" | "en" | "ja" | "ko" | ...
    // 默认使用系统当前设置的主语言
    var speechRecognitionLanguage: String {
        didSet { defaults.set(speechRecognitionLanguage, forKey: "speechRecognitionLanguage") }
    }
    
    var voiceBackgroundDuration: Int {
        didSet { defaults.set(voiceBackgroundDuration, forKey: "voiceBackgroundDuration") }
    }
    
    // Whisper 推理模式: true = CPU only, false = CPU + GPU
    // GPU 模式识别质量更好，CPU 模式支持后台运行
    var whisperUseCPUOnly: Bool {
        didSet { 
            defaults.set(whisperUseCPUOnly, forKey: "whisperUseCPUOnly")
            // 切换模式后需要重新加载模型
            WhisperService.shared.unload()
        }
    }
    
    // Whisper 解码参数
    var whisperTemperature: Double {
        didSet { defaults.set(whisperTemperature, forKey: "whisperTemperature") }
    }
    var whisperFallbackCount: Int {
        didSet { defaults.set(whisperFallbackCount, forKey: "whisperFallbackCount") }
    }
    var whisperSuppressBlank: Bool {
        didSet { defaults.set(whisperSuppressBlank, forKey: "whisperSuppressBlank") }
    }
    
    // Whisper 阈值设置
    var whisperUseNoSpeechThreshold: Bool {
        didSet { defaults.set(whisperUseNoSpeechThreshold, forKey: "whisperUseNoSpeechThreshold") }
    }
    var whisperNoSpeechThreshold: Double {
        didSet { defaults.set(whisperNoSpeechThreshold, forKey: "whisperNoSpeechThreshold") }
    }
    var whisperUseLogProbThreshold: Bool {
        didSet { defaults.set(whisperUseLogProbThreshold, forKey: "whisperUseLogProbThreshold") }
    }
    var whisperLogProbThreshold: Double {
        didSet { defaults.set(whisperLogProbThreshold, forKey: "whisperLogProbThreshold") }
    }
    var whisperFirstTokenLogProbThreshold: Double {
        didSet { defaults.set(whisperFirstTokenLogProbThreshold, forKey: "whisperFirstTokenLogProbThreshold") }
    }
    var whisperUseCompressionRatioThreshold: Bool {
        didSet { defaults.set(whisperUseCompressionRatioThreshold, forKey: "whisperUseCompressionRatioThreshold") }
    }
    var whisperCompressionRatioThreshold: Double {
        didSet { defaults.set(whisperCompressionRatioThreshold, forKey: "whisperCompressionRatioThreshold") }
    }

    // Provider-specific defaults
    static let providerDefaults: [String: (baseURL: String, model: String)] = [
        "openai": ("https://api.openai.com/v1", "gpt-4o-mini"),
        "bailian": ("https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus"),
        "custom": ("", "")
    ]
    
    // Whisper 默认参数
    static let whisperDefaults = (
        temperature: 0.0,
        fallbackCount: 5,
        suppressBlank: true,
        useNoSpeechThreshold: true,
        noSpeechThreshold: 0.6,
        useLogProbThreshold: true,
        logProbThreshold: -1.0,
        firstTokenLogProbThreshold: -1.5,
        useCompressionRatioThreshold: true,
        compressionRatioThreshold: 2.4
    )

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

        // 转写引擎设置 - 默认优先使用 SpeechAnalyzer (iOS 26+)
        let defaultEngine: String
        if #available(iOS 26.0, *) {
            defaultEngine = "speechAnalyzer"
        } else {
            defaultEngine = "whisper"
        }
        self.transcriptionEngine = defaults.string(forKey: "transcriptionEngine") ?? defaultEngine
        
        self.llmProvider = defaults.string(forKey: "llmProvider") ?? "openai"
        self.llmAPIKey = defaults.string(forKey: "llmAPIKey") ?? ""
        self.llmBaseURL = defaults.string(forKey: "llmBaseURL") ?? Self.providerDefaults["openai"]!.baseURL
        self.llmModel = defaults.string(forKey: "llmModel") ?? Self.providerDefaults["openai"]!.model
        self.targetLanguage = defaults.string(forKey: "targetLanguage") ?? AppConstants.defaultTargetLanguage
        // 默认使用系统当前语言，如果无法获取则使用 "auto"
        let systemLanguage = Locale.current.language.languageCode?.identifier ?? "auto"
        let defaultLanguage = Self.supportedLanguages.contains(systemLanguage) ? systemLanguage : "auto"
        self.speechRecognitionLanguage = defaults.string(forKey: "speechRecognitionLanguage") ?? defaultLanguage
        let bgDur = defaults.integer(forKey: "voiceBackgroundDuration")
        self.voiceBackgroundDuration = bgDur > 0 ? bgDur : AppConstants.defaultVoiceBackgroundDuration
        
        // Whisper 设置 - 默认使用 GPU 模式
        self.whisperUseCPUOnly = defaults.object(forKey: "whisperUseCPUOnly") as? Bool ?? false
        self.whisperTemperature = defaults.object(forKey: "whisperTemperature") as? Double ?? Self.whisperDefaults.temperature
        self.whisperFallbackCount = defaults.object(forKey: "whisperFallbackCount") as? Int ?? Self.whisperDefaults.fallbackCount
        self.whisperSuppressBlank = defaults.object(forKey: "whisperSuppressBlank") as? Bool ?? Self.whisperDefaults.suppressBlank
        self.whisperUseNoSpeechThreshold = defaults.object(forKey: "whisperUseNoSpeechThreshold") as? Bool ?? Self.whisperDefaults.useNoSpeechThreshold
        self.whisperNoSpeechThreshold = defaults.object(forKey: "whisperNoSpeechThreshold") as? Double ?? Self.whisperDefaults.noSpeechThreshold
        self.whisperUseLogProbThreshold = defaults.object(forKey: "whisperUseLogProbThreshold") as? Bool ?? Self.whisperDefaults.useLogProbThreshold
        self.whisperLogProbThreshold = defaults.object(forKey: "whisperLogProbThreshold") as? Double ?? Self.whisperDefaults.logProbThreshold
        self.whisperFirstTokenLogProbThreshold = defaults.object(forKey: "whisperFirstTokenLogProbThreshold") as? Double ?? Self.whisperDefaults.firstTokenLogProbThreshold
        self.whisperUseCompressionRatioThreshold = defaults.object(forKey: "whisperUseCompressionRatioThreshold") as? Bool ?? Self.whisperDefaults.useCompressionRatioThreshold
        self.whisperCompressionRatioThreshold = defaults.object(forKey: "whisperCompressionRatioThreshold") as? Double ?? Self.whisperDefaults.compressionRatioThreshold
    }

    func reload() {
        // 转写引擎设置
        let defaultEngine: String
        if #available(iOS 26.0, *) {
            defaultEngine = "speechAnalyzer"
        } else {
            defaultEngine = "whisper"
        }
        transcriptionEngine = defaults.string(forKey: "transcriptionEngine") ?? defaultEngine
        
        llmProvider = defaults.string(forKey: "llmProvider") ?? "openai"
        llmAPIKey = defaults.string(forKey: "llmAPIKey") ?? ""
        llmBaseURL = defaults.string(forKey: "llmBaseURL") ?? Self.providerDefaults["openai"]!.baseURL
        llmModel = defaults.string(forKey: "llmModel") ?? Self.providerDefaults["openai"]!.model
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? AppConstants.defaultTargetLanguage
        let systemLanguage = Locale.current.language.languageCode?.identifier ?? "auto"
        let defaultLanguage = Self.supportedLanguages.contains(systemLanguage) ? systemLanguage : "auto"
        speechRecognitionLanguage = defaults.string(forKey: "speechRecognitionLanguage") ?? defaultLanguage
        let bgDur = defaults.integer(forKey: "voiceBackgroundDuration")
        voiceBackgroundDuration = bgDur > 0 ? bgDur : AppConstants.defaultVoiceBackgroundDuration
        
        // Whisper 设置
        whisperUseCPUOnly = defaults.object(forKey: "whisperUseCPUOnly") as? Bool ?? false
        whisperTemperature = defaults.object(forKey: "whisperTemperature") as? Double ?? Self.whisperDefaults.temperature
        whisperFallbackCount = defaults.object(forKey: "whisperFallbackCount") as? Int ?? Self.whisperDefaults.fallbackCount
        whisperSuppressBlank = defaults.object(forKey: "whisperSuppressBlank") as? Bool ?? Self.whisperDefaults.suppressBlank
        whisperUseNoSpeechThreshold = defaults.object(forKey: "whisperUseNoSpeechThreshold") as? Bool ?? Self.whisperDefaults.useNoSpeechThreshold
        whisperNoSpeechThreshold = defaults.object(forKey: "whisperNoSpeechThreshold") as? Double ?? Self.whisperDefaults.noSpeechThreshold
        whisperUseLogProbThreshold = defaults.object(forKey: "whisperUseLogProbThreshold") as? Bool ?? Self.whisperDefaults.useLogProbThreshold
        whisperLogProbThreshold = defaults.object(forKey: "whisperLogProbThreshold") as? Double ?? Self.whisperDefaults.logProbThreshold
        whisperFirstTokenLogProbThreshold = defaults.object(forKey: "whisperFirstTokenLogProbThreshold") as? Double ?? Self.whisperDefaults.firstTokenLogProbThreshold
        whisperUseCompressionRatioThreshold = defaults.object(forKey: "whisperUseCompressionRatioThreshold") as? Bool ?? Self.whisperDefaults.useCompressionRatioThreshold
        whisperCompressionRatioThreshold = defaults.object(forKey: "whisperCompressionRatioThreshold") as? Double ?? Self.whisperDefaults.compressionRatioThreshold
    }
    
    func resetWhisperSettings() {
        whisperUseCPUOnly = false
        whisperTemperature = Self.whisperDefaults.temperature
        whisperFallbackCount = Self.whisperDefaults.fallbackCount
        whisperSuppressBlank = Self.whisperDefaults.suppressBlank
        whisperUseNoSpeechThreshold = Self.whisperDefaults.useNoSpeechThreshold
        whisperNoSpeechThreshold = Self.whisperDefaults.noSpeechThreshold
        whisperUseLogProbThreshold = Self.whisperDefaults.useLogProbThreshold
        whisperLogProbThreshold = Self.whisperDefaults.logProbThreshold
        whisperFirstTokenLogProbThreshold = Self.whisperDefaults.firstTokenLogProbThreshold
        whisperUseCompressionRatioThreshold = Self.whisperDefaults.useCompressionRatioThreshold
        whisperCompressionRatioThreshold = Self.whisperDefaults.compressionRatioThreshold
        WhisperService.shared.unload()
    }
    
    /// 获取当前转写引擎类型
    var currentTranscriptionEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: transcriptionEngine) ?? .whisper
    }
    
    /// 切换转写引擎时清理资源
    private func unloadTranscriptionEngine() {
        WhisperService.shared.unload()
        if #available(iOS 26.0, *) {
            SpeechAnalyzerService.shared.unload()
        }
        Logger.keyboardInfo("Transcription engine unloaded due to engine switch")
    }
    
    /// 重置转写引擎为默认值（根据系统版本）
    func resetTranscriptionEngineToDefault() {
        if #available(iOS 26.0, *) {
            transcriptionEngine = TranscriptionEngine.speechAnalyzer.rawValue
        } else {
            transcriptionEngine = TranscriptionEngine.whisper.rawValue
        }
    }
    private func applyProviderDefaults() {
        guard let providerDefault = Self.providerDefaults[llmProvider] else { return }
        if llmProvider != "custom" {
            llmBaseURL = providerDefault.baseURL
            llmModel = providerDefault.model
        }
    }
    
    // 支持的语言代码列表
    static let supportedLanguages = ["auto", "zh", "en", "ja", "ko", "fr", "de", "es"]
}
