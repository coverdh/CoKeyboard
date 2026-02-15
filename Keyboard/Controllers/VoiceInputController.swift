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
    var onAudioLevelUpdated: ((Float) -> Void)?     // 音频电平更新
    var onProgressUpdated: ((Float) -> Void)?       // 处理进度更新

    private(set) var currentState: KeyboardInputState = .idle {
        didSet { 
            Logger.stateChange(from: stateDescription(oldValue), to: stateDescription(currentState))
            onStateChanged?(currentState) 
        }
    }

    private var whisperTokens = 0
    private var polishTokens = 0
    private var pollTimer: Timer?

    private var capturingRequestTime: Date?  // 请求开始采集的时间
    private let capturingTimeout: TimeInterval = 0.8  // 等待主 App 响应的超时时间（缩短以更快响应）

    init() {
        Logger.keyboardInfo("VoiceInputController initialized")
        // 清理残留的处理状态，但保留录音状态
        cleanupStaleState()
        // 检查是否有待处理的结果
        if sessionManager.processingStatus == .done {
            if let result = sessionManager.consumePendingResult(), !result.isEmpty {
                Logger.processingInfo("Found pending result on init: \(result.prefix(50))...")
                // 结果会在 onTextReady 设置后通知
            }
            sessionManager.processingStatus = .idle
        }
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
        let isCapturing = sessionManager.isCapturing
        let processingStatus = sessionManager.processingStatus
        
        // 轮询音频电平 (采集时)
        if isCapturing {
            let audioLevel = sessionManager.currentAudioLevel
            onAudioLevelUpdated?(audioLevel)
        }
        
        // 轮询处理进度 (处理时)
        if processingStatus == .transcribing || processingStatus == .polishing {
            let progress = sessionManager.processingProgress
            onProgressUpdated?(progress)
        }
        
        // 优先检查 processingStatus，避免处理中被 isRecording 状态覆盖
        switch processingStatus {
        case .transcribing:
            if case .transcribing = currentState { } else {
                Logger.processingInfo("Main app is transcribing")
                currentState = .transcribing
            }
            return
        case .polishing:
            if case .polishing = currentState { } else {
                Logger.processingInfo("Main app is polishing")
                currentState = .polishing
            }
            return
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
            return
        case .error:
            Logger.processingError("Main app reported processing error")
            currentState = .error("Processing failed")
            sessionManager.processingStatus = .idle
            resetAfterDelay()
            return
        case .recording, .idle:
            // 继续检查录音状态
            break
        }
        
        // 检查是否正在采集音频（用户点击录制后的实际采集状态）
        if isCapturing {
            capturingRequestTime = nil  // 清除请求时间，主 App 已响应
            if case .recording = currentState {
                // Already in recording state
            } else {
                Logger.recordingInfo("Detected main app is capturing audio")
                currentState = .recording
            }
            return
        }
        
        // 检查是否正在等待主 App 开始采集
        if case .recording = currentState, let requestTime = capturingRequestTime {
            let elapsed = Date().timeIntervalSince(requestTime)
            if elapsed > capturingTimeout {
                // 超时：主 App 没有响应，可能已被杀死或 AVAudioSession 失效
                Logger.recordingInfo("Capture request timed out after \(elapsed)s, main app may not be running")
                capturingRequestTime = nil
                // 重置共享状态，强制跳转主 App
                sessionManager.stopRecording()
                currentState = .idle
                // 自动触发跳转主 App
                triggerSessionActivation()
            }
            return
        }
        
        // 如果 processingStatus 是 idle 且不在采集，重置状态
        if processingStatus == .idle {
            if case .transcribing = currentState {
                Logger.keyboardInfo("Resetting from transcribing to idle")
                currentState = .idle
            } else if case .polishing = currentState {
                Logger.keyboardInfo("Resetting from polishing to idle")
                currentState = .idle
            } else if case .recording = currentState {
                // 如果之前在录制但现在不在采集了，重置为 idle
                Logger.keyboardInfo("Resetting from recording to idle (capture stopped)")
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
        Logger.keyboardInfo("isRecording: \(sessionManager.isRecording), isCapturing: \(sessionManager.isCapturing), shouldStop: \(sessionManager.shouldStopRecording)")
        
        switch currentState {
        case .idle, .needsSession, .error:
            // Check if main app has active recording session (within idle timeout)
            let settings = AppSettings.shared
            let isSessionActive = sessionManager.isRecordingStillActive(maxIdleSeconds: settings.voiceBackgroundDuration)
            
            if isSessionActive {
                // 系统录音仍在保持时间内，可以直接开始采集
                Logger.recordingInfo("Recording session is still active, starting capture directly")
                // 通知主 App 重新开始采集
                requestStartCapturing()
            } else {
                // 需要跳转主 App 启动系统录音
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
    
    /// 请求主 App 开始采集（系统录音已处于活跃状态）
    private func requestStartCapturing() {
        Logger.recordingInfo("Requesting start capturing")
        // 重置停止信号，让主 App 知道可以开始采集了
        sessionManager.shouldStopRecording = false
        // 记录请求时间，用于超时检测
        capturingRequestTime = Date()
        // 更新状态为录音中，等待主 App 开始采集
        // 如果主 App 在超时时间内没有响应，会自动跳转主 App
        currentState = .recording
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
