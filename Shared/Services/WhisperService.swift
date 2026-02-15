import Foundation
import WhisperKit

final class WhisperService {
    static let shared = WhisperService()

    private var whisperKit: WhisperKit?
    private var isLoading = false
    
    // 内置模型名称
    private let modelName = "openai_whisper-tiny"

    private init() {}

    var isReady: Bool {
        whisperKit != nil
    }
    
    /// 获取内置模型路径
    private func bundledModelPath() -> String? {
        // 模型文件直接位于 App Bundle 根目录
        // 检查 AudioEncoder.mlmodelc 是否存在来验证模型
        let bundlePath = Bundle.main.bundlePath
        let audioEncoderPath = (bundlePath as NSString).appendingPathComponent("AudioEncoder.mlmodelc")
        
        if FileManager.default.fileExists(atPath: audioEncoderPath) {
            return bundlePath
        }
        
        // 尝试在 Models 子目录中查找
        if let modelsPath = Bundle.main.path(forResource: "Models", ofType: nil) {
            let modelPath = (modelsPath as NSString).appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: modelPath) {
                return modelPath
            }
        }
        
        return nil
    }

    func prepare() async throws {
        guard whisperKit == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // 使用内置模型，完全离线运行
        guard let modelPath = bundledModelPath() else {
            throw WhisperServiceError.modelNotFound
        }
        
        let config = WhisperKitConfig(
            modelFolder: modelPath,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU,
                prefillCompute: .cpuAndGPU
            ),
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: false  // 禁用下载，使用内置模型
        )
        whisperKit = try await WhisperKit(config)
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        if whisperKit == nil {
            try await prepare()
        }

        guard let kit = whisperKit else {
            throw WhisperServiceError.notReady
        }

        let results = try await kit.transcribe(audioPath: audioURL.path())

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenCount = text.count / 4  // rough estimate

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
