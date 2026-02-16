import Foundation
import WhisperKit
import CoreML

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
        
        // 根据设置选择 CPU 或 GPU 模式
        let useCPUOnly = AppSettings.shared.whisperUseCPUOnly
        let computeUnit: MLComputeUnits = useCPUOnly ? .cpuOnly : .cpuAndGPU
        Logger.keyboardInfo("Using \(useCPUOnly ? "CPU-only" : "CPU+GPU") mode for Whisper")
        
        let config = WhisperKitConfig(
            modelFolder: modelPath,
            computeOptions: ModelComputeOptions(
                melCompute: computeUnit,
                audioEncoderCompute: computeUnit,
                textDecoderCompute: computeUnit,
                prefillCompute: computeUnit
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
            let recognitionLanguage = language ?? settings.speechRecognitionLanguage
            
            if recognitionLanguage == "auto" {
                // 自动检测模式：启用语言检测
                Logger.keyboardInfo("Using automatic language detection")
                return try await performTranscription(kit: kit, audioURL: audioURL, language: nil, detectLanguage: true)
            } else {
                // 指定语言模式
                Logger.keyboardInfo("Using specified language: \(recognitionLanguage)")
                return try await performTranscription(kit: kit, audioURL: audioURL, language: recognitionLanguage, detectLanguage: false)
            }
        } catch {
            Logger.keyboardError("Transcription failed: \(error.localizedDescription)", error: error)
            throw WhisperServiceError.transcriptionFailed
        }
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
    
    /// 执行转录
    private func performTranscription(kit: WhisperKit, audioURL: URL, language: String?, detectLanguage: Bool) async throws -> TranscriptionResult {
        Logger.keyboardInfo("performTranscription starting - language: \(language ?? "auto"), detectLanguage: \(detectLanguage)")
        
        // 根据设置构建 DecodingOptions
        let settings = AppSettings.shared
        let options = DecodingOptions(
            verbose: true,
            task: .transcribe,
            language: language,
            temperature: Float(settings.whisperTemperature),
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: settings.whisperFallbackCount,
            sampleLength: 224,
            topK: 5,
            usePrefillPrompt: language != nil,
            usePrefillCache: language != nil,
            detectLanguage: detectLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            clipTimestamps: [],
            suppressBlank: settings.whisperSuppressBlank,
            supressTokens: [],
            compressionRatioThreshold: settings.whisperUseCompressionRatioThreshold ? Float(settings.whisperCompressionRatioThreshold) : nil,
            logProbThreshold: settings.whisperUseLogProbThreshold ? Float(settings.whisperLogProbThreshold) : nil,
            firstTokenLogProbThreshold: settings.whisperUseLogProbThreshold ? Float(settings.whisperFirstTokenLogProbThreshold) : nil,
            noSpeechThreshold: settings.whisperUseNoSpeechThreshold ? Float(settings.whisperNoSpeechThreshold) : 1.0
        )
        
        Logger.keyboardInfo("Starting WhisperKit transcription...")
        let results = try await kit.transcribe(audioPath: audioURL.path(), decodeOptions: options)
        Logger.keyboardInfo("WhisperKit transcription completed, got \(results.count) result segments")
        
        // 详细输出每个结果段
        for (index, result) in results.enumerated() {
            Logger.keyboardInfo("Segment \(index): text=\"\(result.text)\"")
        }
        
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        Logger.keyboardInfo("Raw transcription text: \"\(text)\"")
        
        let tokenCount = text.count / 4
        
        // 清理结果中可能的标记
        let cleanedText = cleanTranscriptionResult(text)
        Logger.keyboardInfo("Cleaned transcription text: \"\(cleanedText)\"")
        
        Logger.keyboardInfo("Transcription result: \(cleanedText.prefix(50))...")
        return AppTranscriptionResult(text: cleanedText, tokenCount: tokenCount)
    }

    func unload() {
        whisperKit = nil
    }
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
