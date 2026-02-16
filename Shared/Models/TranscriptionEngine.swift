import Foundation

/// 转写引擎类型
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case speechAnalyzer = "speechAnalyzer"
    case whisper = "whisper"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .speechAnalyzer:
            return "SpeechAnalyzer (iOS 26+)"
        case .whisper:
            return "Whisper (本地模型)"
        }
    }
    
    var description: String {
        switch self {
        case .speechAnalyzer:
            return "使用 iOS 26 系统内置语音识别，无需额外模型，响应更快"
        case .whisper:
            return "使用 OpenAI Whisper 本地模型，支持更多语言，准确率更高"
        }
    }
    
    /// 检查当前系统是否支持
    var isSupported: Bool {
        switch self {
        case .speechAnalyzer:
            if #available(iOS 26.0, *) {
                return true
            }
            return false
        case .whisper:
            return true
        }
    }
}
