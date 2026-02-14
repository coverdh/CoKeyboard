import Foundation
import WhisperKit

final class WhisperService {
    static let shared = WhisperService()

    private var whisperKit: WhisperKit?
    private var isLoading = false

    private init() {}

    var isReady: Bool {
        whisperKit != nil
    }

    func prepare() async throws {
        guard whisperKit == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let config = WhisperKitConfig(model: "openai_whisper-tiny")
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
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .notReady: return "Whisper model is not loaded"
        case .transcriptionFailed: return "Transcription failed"
        }
    }
}
