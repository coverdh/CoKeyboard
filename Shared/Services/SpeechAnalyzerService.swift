import Foundation
import Speech
import AVFoundation

/// iOS 26+ SpeechAnalyzer 转写服务
/// 使用系统内置的 SpeechAnalyzer 框架进行本地语音识别
@available(iOS 26.0, *)
final class SpeechAnalyzerService {
    static let shared = SpeechAnalyzerService()
    
    private var speechAnalyzer: SpeechAnalyzer?
    private var isLoading = false
    
    private init() {}
    
    var isReady: Bool {
        speechAnalyzer != nil
    }
    
    /// 准备 SpeechAnalyzer
    func prepare() async throws {
        guard speechAnalyzer == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        Logger.keyboardInfo("Initializing SpeechAnalyzer...")
        
        do {
            // 获取当前语言设置
            let settings = AppSettings.shared
            let recognitionLanguage = settings.speechRecognitionLanguage
            var locale: Locale?
            if recognitionLanguage != "auto" {
                locale = Locale(identifier: recognitionLanguage)
            }
            
            // 创建 SpeechAnalyzer 实例
            let analyzer = try await SpeechAnalyzer(locale: locale)
            self.speechAnalyzer = analyzer
            Logger.keyboardInfo("SpeechAnalyzer initialized successfully")
        } catch {
            Logger.keyboardError("Failed to initialize SpeechAnalyzer: \(error.localizedDescription)", error: error)
            throw SpeechAnalyzerError.initializationFailed
        }
    }
    
    /// 转写音频文件
    func transcribe(audioURL: URL, language: String? = nil) async throws -> AppTranscriptionResult {
        if speechAnalyzer == nil {
            Logger.keyboardInfo("SpeechAnalyzer not initialized, preparing...")
            try await prepare()
        }
        
        guard let analyzer = speechAnalyzer else {
            Logger.keyboardError("SpeechAnalyzer is nil after prepare")
            throw SpeechAnalyzerError.notReady
        }
        
        Logger.keyboardInfo("Starting SpeechAnalyzer transcription for: \(audioURL.path)")
        
        // 检查音频文件
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Logger.keyboardError("Audio file does not exist")
            throw SpeechAnalyzerError.audioFileNotFound
        }
        
        do {
            // 配置识别选项
            let settings = AppSettings.shared
            let recognitionLanguage = language ?? settings.speechRecognitionLanguage
            
            // 设置语言区域
            var locale: Locale?
            if recognitionLanguage != "auto" {
                locale = Locale(identifier: recognitionLanguage)
                Logger.keyboardInfo("Using specified language: \(recognitionLanguage)")
            } else {
                Logger.keyboardInfo("Using automatic language detection")
            }
            
            // 执行转写
            Logger.keyboardInfo("Starting SpeechAnalyzer transcription...")
            let text = try await analyzer.transcribe(audioURL, locale: locale)
            
            Logger.keyboardInfo("SpeechAnalyzer transcription completed: \"\(text.prefix(50))...\"")
            
            // 估算 token 数量（SpeechAnalyzer 不直接提供 token 计数）
            let tokenCount = estimateTokenCount(for: text)
            
            return AppTranscriptionResult(text: text, tokenCount: tokenCount)
            
        } catch {
            Logger.keyboardError("SpeechAnalyzer transcription failed: \(error.localizedDescription)", error: error)
            throw SpeechAnalyzerError.transcriptionFailed
        }
    }
    
    /// 估算 token 数量（用于统计）
    private func estimateTokenCount(for text: String) -> Int {
        // 简单估算：英文约 4 字符/token，中文约 1 字符/token
        // 这里使用一个混合估算方式
        let characterCount = text.count
        return max(1, characterCount / 3)
    }
    
    /// 清理资源
    func unload() {
        speechAnalyzer = nil
        Logger.keyboardInfo("SpeechAnalyzer unloaded")
    }
}

// MARK: - Errors

enum SpeechAnalyzerError: LocalizedError {
    case notReady
    case initializationFailed
    case audioFileNotFound
    case transcriptionFailed
    case unsupportedOSVersion
    
    var errorDescription: String? {
        switch self {
        case .notReady:
            return "SpeechAnalyzer is not ready"
        case .initializationFailed:
            return "Failed to initialize SpeechAnalyzer"
        case .audioFileNotFound:
            return "Audio file not found"
        case .transcriptionFailed:
            return "Transcription failed"
        case .unsupportedOSVersion:
            return "SpeechAnalyzer requires iOS 26 or later"
        }
    }
}

// MARK: - iOS 26+ SpeechAnalyzer Support

// 注意：iOS 26 引入了 SpeechAnalyzer 框架
// 由于这是一个新框架，我们使用 SFSpeechRecognizer 作为备选方案
// 当 SpeechAnalyzer 正式可用时，可以替换实现

#if compiler(>=6.2)

// iOS 26+ 使用新的 Speech 框架
import Speech

@available(iOS 26.0, *)
public struct SpeechAnalyzer {
    private let speechRecognizer: SFSpeechRecognizer?
    
    private let locale: Locale?
    
    public init(locale: Locale? = nil) async throws {
        self.locale = locale
        
        // 请求语音识别权限
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard authStatus == .authorized else {
            throw SpeechAnalyzerError.initializationFailed
        }
        
        // 根据 locale 创建对应的 recognizer
        if let locale = locale {
            self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        } else {
            self.speechRecognizer = SFSpeechRecognizer()
        }
        
        guard speechRecognizer != nil else {
            throw SpeechAnalyzerError.initializationFailed
        }
    }
    
    public func transcribe(_ audioURL: URL, locale: Locale?) async throws -> String {
        guard let speechRecognizer = speechRecognizer else {
            throw SpeechAnalyzerError.initializationFailed
        }
        
        // 创建识别请求
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true // 本地识别
        
        // 执行识别
        return try await withCheckedThrowingContinuation { continuation in
            let recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else {
                    continuation.resume(throwing: SpeechAnalyzerError.transcriptionFailed)
                    return
                }
                
                if result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
            
            // 设置超时
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak recognitionTask] in
                recognitionTask?.cancel()
            }
        }
    }
}

#else

// 对于旧版本编译器，提供空实现
@available(iOS 26.0, *)
public struct SpeechAnalyzer {
    public init() async throws {
        throw SpeechAnalyzerError.unsupportedOSVersion
    }
    
    public func transcribe(_ audioURL: URL, locale: Locale?) async throws -> String {
        throw SpeechAnalyzerError.unsupportedOSVersion
    }
}

#endif
