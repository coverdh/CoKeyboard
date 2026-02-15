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
        didSet { 
            Logger.stateChange(from: stateDescription(oldValue), to: stateDescription(currentState))
            onStateChanged?(currentState) 
        }
    }

    private var whisperTokens = 0
    private var polishTokens = 0
    private var pollTimer: Timer?

    init() {
        Logger.keyboardInfo("VoiceInputController initialized")
        // 强制重置所有共享状态（调试用）
        sessionManager.reset()
        // 默认状态为等待录制
        currentState = .idle
        startPolling()
    }
    
    /// 清理残留的共享状态
    private func cleanupStaleState() {
        // 如果主 App 没有在录音，但 processingStatus 不是 idle/done，说明是残留状态
        if !sessionManager.isRecording {
            let status = sessionManager.processingStatus
            if status == .transcribing || status == .polishing || status == .recording {
                Logger.keyboardInfo("Cleaning up stale processingStatus: \(status.rawValue)")
                sessionManager.processingStatus = .idle
            }
        }
    }
    
    deinit {
        pollTimer?.invalidate()
        Logger.keyboardInfo("VoiceInputController deinitialized")
    }
    
    private func stateDescription(_ state: KeyboardInputState) -> String {
        switch state {
        case .idle: return "idle"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        case .polishing: return "polishing"
        case .translating: return "translating"
        case .needsSession: return "needsSession"
        case .error(let msg): return "error(\(msg))"
        }
    }

    // MARK: - Polling for shared state
    
    private func startPolling() {
        Logger.keyboardInfo("Starting state polling (interval: 0.5s)")
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkSharedState()
        }
    }
    
    private func checkSharedState() {
        let isRecording = sessionManager.isRecording
        let processingStatus = sessionManager.processingStatus
        
        // Check if main app is recording
        if isRecording {
            if case .recording = currentState {
                // Already in recording state
            } else {
                Logger.recordingInfo("Detected main app is recording")
                currentState = .recording
            }
            return
        }
        
        // Check processing status
        switch processingStatus {
        case .transcribing:
            if case .transcribing = currentState { } else {
                Logger.processingInfo("Main app is transcribing")
                currentState = .transcribing
            }
        case .polishing:
            if case .polishing = currentState { } else {
                Logger.processingInfo("Main app is polishing")
                currentState = .polishing
            }
        case .done:
            Logger.processingInfo("Processing done, consuming result")
            if let result = sessionManager.consumePendingResult() {
                if !result.isEmpty {
                    Logger.processingInfo("Got result: \(result.prefix(50))...")
                    onTextReady?(result)
                } else {
                    Logger.processingInfo("Result was empty")
                }
                sessionManager.processingStatus = .idle
                currentState = .idle
            }
        case .error:
            Logger.processingError("Main app reported processing error")
            currentState = .error("Processing failed")
            sessionManager.processingStatus = .idle
            resetAfterDelay()
        case .recording:
            // Still recording in main app
            break
        case .idle:
            // Only reset to idle if we were in a processing state
            if case .transcribing = currentState {
                Logger.keyboardInfo("Resetting from transcribing to idle")
                currentState = .idle
            } else if case .polishing = currentState {
                Logger.keyboardInfo("Resetting from polishing to idle")
                currentState = .idle
            }
        }
    }

    /// 检查并消费待处理的结果
    func checkPendingResult() {
        Logger.keyboardInfo("Checking for pending result")
        if let result = sessionManager.consumePendingResult(), !result.isEmpty {
            Logger.processingInfo("Found pending result: \(result.prefix(50))...")
            onTextReady?(result)
            sessionManager.processingStatus = .idle
        } else {
            Logger.keyboardInfo("No pending result found")
        }
        
        // Also refresh state
        checkSharedState()
    }

    func toggleRecording() {
        Logger.keyboardInfo("toggleRecording called, current state: \(stateDescription(currentState))")
        Logger.keyboardInfo("isRecording: \(sessionManager.isRecording), shouldStop: \(sessionManager.shouldStopRecording)")
        
        switch currentState {
        case .idle, .needsSession, .error:
            // Check if main app is already recording
            if sessionManager.isRecording {
                Logger.recordingInfo("Main app is recording, requesting stop")
                requestStopRecording()
            } else {
                Logger.recordingInfo("Need to start recording via main app")
                triggerSessionActivation()
            }
        case .recording:
            Logger.recordingInfo("Currently recording, requesting stop")
            requestStopRecording()
        default:
            Logger.keyboardInfo("Ignoring tap - busy processing")
            break
        }
    }
    
    private func requestStopRecording() {
        Logger.recordingInfo("Requesting stop recording")
        sessionManager.requestStopRecording()
        currentState = .transcribing
    }

    private func triggerSessionActivation() {
        Logger.keyboardInfo("Triggering session activation - will jump to main app")
        currentState = .needsSession
        let url = sessionManager.makeActivationURL(sourceBundleID: nil)
        Logger.keyboardInfo("Activation URL: \(url?.absoluteString ?? "nil")")
        onNeedsSession?(url)
    }

    func translate(text: String) {
        guard !text.isEmpty else { 
            Logger.keyboardInfo("Translate called with empty text, ignoring")
            return 
        }
        Logger.processingInfo("Starting translation for: \(text.prefix(30))...")
        currentState = .translating

        Task { @MainActor in
            let translated = await translationService.translate(text: text)
            Logger.processingInfo("Translation completed: \(translated.prefix(30))...")
            onTextReady?(translated)
            currentState = .idle
        }
    }

    private func resetAfterDelay() {
        Logger.keyboardInfo("Will reset to idle after 2 seconds")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if case .error = currentState {
                Logger.keyboardInfo("Resetting from error to idle")
                currentState = .idle
            }
        }
    }
    
    /// 键盘收起时调用，重置到等待录制状态
    func resetToIdle() {
        Logger.keyboardInfo("Keyboard dismissed, resetting to idle state")
        
        // 如果正在录制，停止录制
        if case .recording = currentState {
            Logger.recordingInfo("Was recording, stopping recording on keyboard dismiss")
            sessionManager.requestStopRecording()
        }
        
        // 清理共享状态中的残留处理状态
        cleanupStaleState()
        
        // 重置到等待录制状态
        currentState = .idle
    }
}
