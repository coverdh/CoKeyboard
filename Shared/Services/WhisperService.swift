import Foundation
import WhisperKit

final class WhisperService {
    static let shared = WhisperService()

    private var whisperKit: WhisperKit?
    private var isLoading = false
    
    // 内置模型名称 (base 模型对中英文混合识别效果更好)
    private let modelName = "openai_whisper-base"

    private init() {}

    var isReady: Bool {
        whisperKit != nil
    }
    
    /// 获取内置模型路径
    private func bundledModelPath() -> String? {
        let bundlePath = Bundle.main.bundlePath
        
        // 首先检查标准位置: Models/openai_whisper-tiny
        if let modelsPath = Bundle.main.path(forResource: "Models", ofType: nil) {
            let modelPath = (modelsPath as NSString).appendingPathComponent(modelName)
            let audioEncoderPath = (modelPath as NSString).appendingPathComponent("AudioEncoder.mlmodelc")
            
            Logger.keyboardInfo("Checking standard model path: \(modelPath)")
            if FileManager.default.fileExists(atPath: audioEncoderPath) {
                Logger.keyboardInfo("Found model at standard location: \(modelPath)")
                return modelPath
            }
        }
        
        // 如果标准位置不存在，检查是否文件被扁平化到 Bundle 根目录
        // 尝试将文件复制到正确的位置
        let audioEncoderAtRoot = (bundlePath as NSString).appendingPathComponent("AudioEncoder.mlmodelc")
        let tokenizerAtRoot = (bundlePath as NSString).appendingPathComponent("tokenizer.json")
        let configAtRoot = (bundlePath as NSString).appendingPathComponent("config.json")
        
        if FileManager.default.fileExists(atPath: audioEncoderAtRoot) &&
           FileManager.default.fileExists(atPath: tokenizerAtRoot) {
            Logger.keyboardInfo("Found flattened model at bundle root, attempting to reorganize...")
            
            // 尝试在 Documents 目录创建正确的模型结构
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let modelURL = documentsPath.appendingPathComponent("Models/\(modelName)")
                let modelPath = modelURL.path
                
                // 如果目标目录已经存在且完整，直接使用
                let audioEncoderPath = (modelPath as NSString).appendingPathComponent("AudioEncoder.mlmodelc")
                if FileManager.default.fileExists(atPath: audioEncoderPath) {
                    Logger.keyboardInfo("Using existing reorganized model at: \(modelPath)")
                    return modelPath
                }
                
                // 创建目录结构
                try? FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
                
                // 复制所有模型文件
                let filesToCopy = [
                    "AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc",
                    "tokenizer.json", "tokenizer_config.json", "preprocessor_config.json",
                    "config.json", "vocab.json", "merges.txt",
                    "added_tokens.json", "special_tokens_map.json", "normalizer.json",
                    "generation_config.json"
                ]
                
                for file in filesToCopy {
                    let sourcePath = (bundlePath as NSString).appendingPathComponent(file)
                    let destPath = (modelPath as NSString).appendingPathComponent(file)
                    
                    if FileManager.default.fileExists(atPath: sourcePath) {
                        try? FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
                    }
                }
                
                // 验证复制是否成功
                if FileManager.default.fileExists(atPath: audioEncoderPath) {
                    Logger.keyboardInfo("Successfully reorganized model at: \(modelPath)")
                    return modelPath
                }
            }
            
            // 如果无法重新组织，直接使用 Bundle 根目录
            Logger.keyboardInfo("Using flattened model at bundle root: \(bundlePath)")
            return bundlePath
        }
        
        // 检查 App Group 容器
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) {
            let modelPath = containerURL.appendingPathComponent("Models/\(modelName)").path
            let audioEncoderPath = (modelPath as NSString).appendingPathComponent("AudioEncoder.mlmodelc")
            
            Logger.keyboardInfo("Checking App Group model path: \(modelPath)")
            if FileManager.default.fileExists(atPath: audioEncoderPath) {
                Logger.keyboardInfo("Found model in App Group: \(modelPath)")
                return modelPath
            }
        }
        
        Logger.keyboardError("Bundled model not found in any location")
        return nil
    }

    func prepare() async throws {
        guard whisperKit == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // 使用内置模型，完全离线运行
        guard let modelPath = bundledModelPath() else {
            Logger.keyboardError("Model not found in bundle")
            throw WhisperServiceError.modelNotFound
        }
        
        Logger.keyboardInfo("Loading Whisper model from: \(modelPath)")
        
        // 检查并列出模型目录中的所有文件
        if let files = try? FileManager.default.contentsOfDirectory(atPath: modelPath) {
            Logger.keyboardInfo("Model directory contents: \(files)")
        }
        
        // 设置 Hugging Face 缓存目录为模型目录，这样 WhisperKit 会在这里查找 tokenizer
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let hubCachePath = documentsPath.appendingPathComponent("huggingface/models/openai/whisper-base")
            try? FileManager.default.createDirectory(at: hubCachePath, withIntermediateDirectories: true)
            
            // 复制 tokenizer 文件到 Hugging Face 缓存目录
            let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json", "preprocessor_config.json",
                                  "config.json", "vocab.json", "merges.txt",
                                  "added_tokens.json", "special_tokens_map.json", "normalizer.json",
                                  "generation_config.json"]
            for file in tokenizerFiles {
                let sourcePath = (modelPath as NSString).appendingPathComponent(file)
                let destPath = hubCachePath.appendingPathComponent(file).path
                if FileManager.default.fileExists(atPath: sourcePath) {
                    if !FileManager.default.fileExists(atPath: destPath) {
                        try? FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
                        Logger.keyboardInfo("Copied \(file) to HuggingFace cache")
                    }
                } else {
                    Logger.keyboardInfo("Source file not found: \(sourcePath)")
                }
            }
            
            // 创建 tokenizer_config.json 如果不存在（WhisperKit 可能需要这个文件）
            let tokenizerConfigPath = hubCachePath.appendingPathComponent("tokenizer_config.json").path
            if !FileManager.default.fileExists(atPath: tokenizerConfigPath) {
                // 创建一个简单的 tokenizer_config.json
                let tokenizerConfig: [String: Any] = [
                    "tokenizer_class": "WhisperTokenizer",
                    "bos_token": "<|endoftext|>",
                    "eos_token": "<|endoftext|>",
                    "pad_token": "<|endoftext|>",
                    "model_max_length": 448
                ]
                if let data = try? JSONSerialization.data(withJSONObject: tokenizerConfig, options: .prettyPrinted) {
                    try? data.write(to: URL(fileURLWithPath: tokenizerConfigPath))
                    Logger.keyboardInfo("Created tokenizer_config.json")
                }
            }
            
            // 创建 preprocessor_config.json 如果不存在
            let preprocessorConfigPath = hubCachePath.appendingPathComponent("preprocessor_config.json").path
            if !FileManager.default.fileExists(atPath: preprocessorConfigPath) {
                let preprocessorConfig: [String: Any] = [
                    "feature_extractor_type": "WhisperFeatureExtractor",
                    "num_mel_bins": 80,
                    "padding_value": 0.0,
                    "return_attention_mask": false
                ]
                if let data = try? JSONSerialization.data(withJSONObject: preprocessorConfig, options: .prettyPrinted) {
                    try? data.write(to: URL(fileURLWithPath: preprocessorConfigPath))
                    Logger.keyboardInfo("Created preprocessor_config.json")
                }
            }
            
            // 设置环境变量指定 Hugging Face 缓存位置
            setenv("HF_HOME", documentsPath.appendingPathComponent("huggingface").path, 1)
            
            // 列出缓存目录内容以确认文件已复制
            if let cacheFiles = try? FileManager.default.contentsOfDirectory(atPath: hubCachePath.path) {
                Logger.keyboardInfo("HuggingFace cache contents: \(cacheFiles)")
            }
        }
        
        let config = WhisperKitConfig(
            modelFolder: modelPath,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU,
                prefillCompute: .cpuAndGPU
            ),
            verbose: true,
            logLevel: .debug,
            prewarm: true,
            load: true,
            download: false,  // 禁用下载，使用内置模型
            useBackgroundDownloadSession: false  // 禁用后台下载
        )
        
        do {
            // 创建 WhisperKit 实例
            let kit = try await WhisperKit(config)
            
            // 确保模型完全加载
            if kit.modelState == .loaded {
                whisperKit = kit
                Logger.keyboardInfo("Whisper model loaded successfully")
            } else {
                Logger.keyboardError("Model state is not loaded: \(kit.modelState)")
                throw WhisperServiceError.modelNotFound
            }
        } catch {
            Logger.keyboardError("Failed to load Whisper model: \(error.localizedDescription)", error: error)
            throw WhisperServiceError.modelNotFound
        }
    }

    func transcribe(audioURL: URL, language: String? = nil) async throws -> TranscriptionResult {
        if whisperKit == nil {
            Logger.keyboardInfo("WhisperKit not loaded, preparing...")
            try await prepare()
        }

        guard let kit = whisperKit else {
            Logger.keyboardError("WhisperKit is nil after prepare")
            throw WhisperServiceError.notReady
        }
        
        Logger.keyboardInfo("Starting transcription for: \(audioURL.path)")

        do {
            let settings = AppSettings.shared
            
            // 检查是否需要中英混合识别模式
            let primaryLang = language ?? settings.speechRecognitionLanguage
            let secondaryLang = settings.speechSecondaryLanguage
            
            // 判断是否为中英混合模式（主语言和辅助语言分别是中文和英文）
            let isMixedMode = isChineseEnglishMixedMode(primary: primaryLang, secondary: secondaryLang)
            
            if isMixedMode {
                // 中英混合模式：使用自动语言检测 + 双语提示词
                Logger.keyboardInfo("Using Chinese-English mixed mode")
                return try await performMixedLanguageTranscription(kit: kit, audioURL: audioURL)
            } else if primaryLang == "auto" {
                // 自动检测模式
                Logger.keyboardInfo("Using automatic language detection")
                return try await performTranscription(kit: kit, audioURL: audioURL, language: nil, prompt: nil)
            } else {
                // 单语言模式
                Logger.keyboardInfo("Using single language mode: \(primaryLang)")
                return try await performTranscription(kit: kit, audioURL: audioURL, language: primaryLang, prompt: nil)
            }
        } catch {
            Logger.keyboardError("Transcription failed: \(error.localizedDescription)", error: error)
            throw WhisperServiceError.transcriptionFailed
        }
    }
    
    /// 判断是否为中英混合模式
    private func isChineseEnglishMixedMode(primary: String, secondary: String?) -> Bool {
        let chineseLanguages = ["zh", "zh-CN", "zh-TW", "zh-HK", "chinese"]
        let englishLanguages = ["en", "en-US", "en-GB", "english"]
        
        let isPrimaryChinese = chineseLanguages.contains { primary.lowercased().hasPrefix($0.lowercased()) }
        let isPrimaryEnglish = englishLanguages.contains { primary.lowercased().hasPrefix($0.lowercased()) }
        
        guard let secondary = secondary else { return false }
        let isSecondaryChinese = chineseLanguages.contains { secondary.lowercased().hasPrefix($0.lowercased()) }
        let isSecondaryEnglish = englishLanguages.contains { secondary.lowercased().hasPrefix($0.lowercased()) }
        
        // 主语言中文+辅助语言英文 或 主语言英文+辅助语言中文
        return (isPrimaryChinese && isSecondaryEnglish) || (isPrimaryEnglish && isSecondaryChinese)
    }
    
    /// 执行中英混合语言转录
    private func performMixedLanguageTranscription(kit: WhisperKit, audioURL: URL) async throws -> TranscriptionResult {
        Logger.keyboardInfo("Performing mixed Chinese-English transcription with detectLanguage=true")
        
        // 中英混合模式的关键设置：
        // 1. language = nil：不指定语言
        // 2. detectLanguage = true：启用语言检测，让模型在每个segment自动识别语言
        // 3. usePrefillPrompt = false：不使用预填充提示，避免强制单一语言
        let options = DecodingOptions(
            verbose: true,
            task: .transcribe,
            language: nil,  // 关键：不指定语言
            temperature: 0.0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 5,
            sampleLength: 224,
            topK: 5,
            usePrefillPrompt: false,  // 关键：禁用预填充，让模型自由检测
            usePrefillCache: false,
            detectLanguage: true,  // 关键：启用语言检测
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            clipTimestamps: [],
            suppressBlank: true,
            supressTokens: [],
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6
        )
        
        let results = try await kit.transcribe(audioPath: audioURL.path(), decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let tokenCount = text.count / 4
        
        // 清理结果中可能的标记
        let cleanedText = cleanTranscriptionResult(text)
        
        Logger.keyboardInfo("Mixed transcription result: \(cleanedText.prefix(50))...")
        return TranscriptionResult(text: cleanedText, tokenCount: tokenCount)
    }
    
    /// 清理转录结果中的标记
    private func cleanTranscriptionResult(_ text: String) -> String {
        var cleaned = text
        
        // 移除常见的无效标记
        let patternsToRemove = [
            "\\[Speaking in foreign language\\]",
            "\\[说外语\\]",
            "\\[BLANK_AUDIO\\]",
            "\\[音乐\\]",
            "\\[Music\\]",
            "\\( 音乐 \\)",
            "\\(音乐\\)"
        ]
        
        for pattern in patternsToRemove {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    options: [],
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            }
        }
        
        // 清理多余的空格
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    /// 执行单次转录（指定语言模式）
    private func performTranscription(kit: WhisperKit, audioURL: URL, language: String?, prompt: String?) async throws -> TranscriptionResult {
        let options: DecodingOptions
        
        if let lang = language {
            Logger.keyboardInfo("Transcribing with specified language: \(lang)")
            options = DecodingOptions(
                verbose: true,
                task: .transcribe,
                language: lang,
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 3,
                sampleLength: 224,
                topK: 5,
                usePrefillPrompt: true,
                usePrefillCache: true,
                detectLanguage: false,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                wordTimestamps: false,
                clipTimestamps: [],
                suppressBlank: true,
                supressTokens: [],
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                noSpeechThreshold: 0.6
            )
        } else {
            // 自动语言检测模式
            Logger.keyboardInfo("Transcribing with automatic language detection")
            options = DecodingOptions(
                verbose: true,
                task: .transcribe,
                language: nil,
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 5,
                sampleLength: 224,
                topK: 5,
                usePrefillPrompt: false,
                usePrefillCache: false,
                detectLanguage: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                wordTimestamps: false,
                clipTimestamps: [],
                suppressBlank: true,
                supressTokens: [],
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                noSpeechThreshold: 0.6
            )
        }
        
        let results = try await kit.transcribe(audioPath: audioURL.path(), decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let tokenCount = text.count / 4
        
        Logger.keyboardInfo("Transcription result: \(text.prefix(50))...")
        return TranscriptionResult(text: text, tokenCount: tokenCount)
    }

    func unload() {
        whisperKit = nil
    }
}

struct TranscriptionResult {
    let text: String
    let tokenCount: Int
}

enum WhisperServiceError: LocalizedError {
    case notReady
    case modelNotFound
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .notReady: return "Whisper model is not loaded"
        case .modelNotFound: return "Bundled Whisper model not found"
        case .transcriptionFailed: return "Transcription failed"
        }
    }
}
