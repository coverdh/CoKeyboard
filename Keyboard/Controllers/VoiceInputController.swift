import Foundation
import SwiftData
import AVFoundation

enum KeyboardInputState {
    case idle
    case recording        // 主App正在后台录音
    case transcribing     // 正在转写
    case polishing        // 正在润色
    case translating      // 正在翻译
    case needsSession     // 需要跳转主App开始录音
    case error(String)
}

final class VoiceInputController {
    private let polishService = PolishService()
    private let translationService = TranslationService()
    private let sessionManager = RecordingSessionManager.shared

    var onStateChanged: ((KeyboardInputState) -> Void)?
    var onTextReady: ((String) -> Void)?
    var onTokensUpdated: ((Int, Int) -> Void)?
    var onNeedsSession: ((URL?) -> Void)?

    private(set) var currentState: KeyboardInputState = .idle {
        didSet { onStateChanged?(currentState) }
    }

    private var whisperTokens = 0
    private var polishTokens = 0
    private var pollTimer: Timer?

    init() {
        // Start polling for state changes
        startPolling()
    }
    
    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Polling for shared state
    
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkSharedState()
        }
    }
    
    private func checkSharedState() {
        // Check if main app is recording
        if sessionManager.isRecording {
            if case .recording = currentState {
                // Already in recording state
            } else {
                currentState = .recording
            }
            return
        }
        
        // Check processing status
        switch sessionManager.processingStatus {
        case .transcribing:
            currentState = .transcribing
        case .polishing:
            currentState = .polishing
        case .done:
            // Consume the result
            if let result = sessionManager.consumePendingResult() {
                if !result.isEmpty {
                    onTextReady?(result)
                }
                sessionManager.processingStatus = .idle
                currentState = .idle
            }
        case .error:
            currentState = .error("Processing failed")
            sessionManager.processingStatus = .idle
            resetAfterDelay()
        default:
            // Only reset to idle if we were in a processing state
            if case .transcribing = currentState {
                currentState = .idle
            } else if case .polishing = currentState {
                currentState = .idle
            }
        }
    }

    /// 检查并消费待处理的结果
    func checkPendingResult() {
        if let result = sessionManager.consumePendingResult(), !result.isEmpty {
            onTextReady?(result)
            sessionManager.processingStatus = .idle
        }
        
        // Also refresh state
        checkSharedState()
    }

    func toggleRecording() {
        switch currentState {
        case .idle, .needsSession, .error:
            // Check if main app is already recording
            if sessionManager.isRecording {
                // Already recording, this tap means stop
                requestStopRecording()
            } else {
                // Need to start recording via main app
                triggerSessionActivation()
            }
        case .recording:
            // Stop recording
            requestStopRecording()
        default:
            break
        }
    }
    
    private func requestStopRecording() {
        sessionManager.requestStopRecording()
        currentState = .transcribing
    }

    private func triggerSessionActivation() {
        currentState = .needsSession
        let url = sessionManager.makeActivationURL(sourceBundleID: nil)
        onNeedsSession?(url)
    }

    func translate(text: String) {
        guard !text.isEmpty else { return }
        currentState = .translating

        Task { @MainActor in
            let translated = await translationService.translate(text: text)
            onTextReady?(translated)
            currentState = .idle
        }
    }

    private func resetAfterDelay() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if case .error = currentState {
                currentState = .idle
            }
        }
    }
}
