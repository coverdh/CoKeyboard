import Foundation

/// 应用级别的转写结果结构体
/// 用于 WhisperService 和 SpeechAnalyzerService 的统一返回类型
/// 注意：避免与 WhisperKit.TranscriptionResult 冲突
struct AppTranscriptionResult {
    let text: String
    let tokenCount: Int
}

// 为了保持向后兼容，添加类型别名
// 在 WhisperKit 导入的上下文中使用 AppTranscriptionResult
typealias TranscriptionResult = AppTranscriptionResult
