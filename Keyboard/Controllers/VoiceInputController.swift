import Foundation
import SwiftData
import AVFoundation

enum KeyboardInputState {
    case idle
    case recording        // 主 App 正在采集音频
    case transcribing     // 正在转写
    case polishing        // 正在润色
    case translating      // 正在翻译
    case needsSession     // 需要跳转主 App 开启录音
    case error(String)
}

final class VoiceInputController {
    private let polishService = PolishService()
    private let translationService = TranslationService()
    private let sessionManager = RecordingSessionManager.shared

    var onStateChanged: ((KeyboardInputState) -> Void)?
    var onTextReady: ((String) -> Void)?
    var onTokensUpdated: ((Int, Int) -> Void)?
    var onNeedsSession: ((URL?) -> Void)?          // 需要跳转主 App
    var onAudioLevelUpdated: ((Float) -> Void)?    // 音频电平更新
    var onProgressUpdated: ((Float) -> Void)?      // 处理进度更新
    
    /// 主 App 录音状态（通过 Darwin Notify 即时同步）
    private var isMainAppRecording = false

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
        
        // 监听 Darwin Notify，即时获取主 App 录音状态
        setupDarwinNotifyObserver()
        
        // 初始化时同步一次状态
        syncRecordingState()
        
        // 清理残留的处理状态
        cleanupStaleState()
        
        // 检查是否有待处理的结果
        if sessionManager.processingStatus == .done {
            if let result = sessionManager.consumePendingResult(), !result.isEmpty {
                Logger.processingInfo("Found pending result on init: \(result.prefix(50))...")
            }
            sessionManager.processingStatus = .idle
        }
        
        // 默认状态为等待录制
        currentState = .idle
        startPolling()
    }
    
    // MARK: - Darwin Notify
    
    private func setupDarwinNotifyObserver() {
        DarwinNotify.observe(DarwinNotify.recordingStateChanged) { [weak self] in
            self?.syncRecordingState()
        }
        Logger.keyboardInfo("Darwin Notify observer setup complete")
    }
    
    /// 同步主 App 录音状态
    private func syncRecordingState() {
        let wasRecording = isMainAppRecording
        isMainAppRecording = sessionManager.isRecording
        Logger.keyboardInfo("Recording state synced: \(wasRecording) -> \(isMainAppRecording)")
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
        DarwinNotify.removeObserver(DarwinNotify.recordingStateChanged)
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
        
        // 检查是否正在采集音频
        if isCapturing {
            if case .recording = currentState {
                // Already in recording state
            } else {
                Logger.recordingInfo("Detected main app is capturing audio")
                currentState = .recording
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
        Logger.keyboardInfo("isMainAppRecording: \(isMainAppRecording), isCapturing: \(sessionManager.isCapturing)")
        
        switch currentState {
        case .idle, .error:
            // 简化判断：如果主 App 正在录音，直接开始采集；否则跳转主 App
            if isMainAppRecording {
                Logger.recordingInfo("Main app is recording, starting capture directly")
                currentState = .recording
                requestStartCapturing()
            } else {
                Logger.recordingInfo("Main app not recording, need to open main app")
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
    
    /// 请求主 App 开始采集
    private func requestStartCapturing() {
        Logger.recordingInfo("Requesting start capturing")
        // 重置停止信号，让主 App 知道可以开始采集了
        sessionManager.shouldStopRecording = false
    }
    
    private func requestStopRecording() {
        Logger.recordingInfo("Requesting stop recording")
        sessionManager.requestStopRecording()
        currentState = .transcribing
    }

    private func triggerSessionActivation() {
        Logger.keyboardInfo("Triggering session activation - will jump to main app")
        // 直接跳转，不需要传递 bundleID，主 App 会使用系统返回功能
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
