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
    case needsOpenAccess  // 需要开启完全访问权限
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
    var onNeedsOpenAccess: (() -> Void)?           // 需要开启完全访问权限
    var onAudioLevelUpdated: ((Float) -> Void)?    // 音频电平更新
    var onProgressUpdated: ((Float) -> Void)?      // 处理进度更新
    
    /// 检查完全访问权限的回调（由 KeyboardViewController 设置）
    var checkOpenAccess: (() -> Bool)?
    
    /// 主 APP 是否活跃（时间戳在 1 秒内）
    private var isMainAppActive: Bool {
        return sessionManager.isMainAppActive
    }
    
    /// 主 APP 是否正在录音（processingStatus 为 recording 且活跃）
    private var isMainAppRecording: Bool {
        return sessionManager.isRecording
    }
    
    /// 是否有完全访问权限
    private var hasOpenAccess: Bool {
        // 优先使用回调检查 (UIInputViewController.hasFullAccess)
        if let check = checkOpenAccess {
            return check()
        }
        // 回退方案：尝试访问 App Groups
        return UserDefaults(suiteName: AppConstants.appGroupID) != nil
    }

    private(set) var currentState: KeyboardInputState = .idle {
        didSet { 
            Logger.stateChange(from: stateDescription(oldValue), to: stateDescription(currentState))
            onStateChanged?(currentState) 
        }
    }

    private var whisperTokens = 0
    private var polishTokens = 0
    private var pollTimer: Timer?
    private var captureStartTime: Date?           // 开始采集的时间，用于超时检测
    private var lastAudioLevel: Float = 0         // 上次音频电平，用于检测主 APP 是否响应

    init() {
        Logger.keyboardInfo("VoiceInputController initialized")
        
        // 监听 Darwin Notify，即时获取主 App 录音状态
        setupDarwinNotifyObserver()
        
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
            self?.onRecordingStateChanged()
        }
        Logger.keyboardInfo("Darwin Notify observer setup complete")
    }
    
    /// 主 APP 状态变化时的回调
    private func onRecordingStateChanged() {
        Logger.keyboardInfo("Recording state changed notification received")
        // 状态会在下次轮询时自动更新
    }
    
    /// 清理残留的共享状态
    private func cleanupStaleState() {
        let status = sessionManager.processingStatus
        
        // 如果主 APP 不活跃，但 processingStatus 不是 idle/done，说明是残留状态
        if !isMainAppActive {
            if status == .transcribing || status == .polishing || status == .recording {
                Logger.keyboardInfo("Cleaning up stale processingStatus (main app inactive): \(status.rawValue)")
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
        case .needsOpenAccess: return "needsOpenAccess"
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
        
        // 检查是否正在采集音频（主 APP 活跃且有音频电平）
        if isCapturing {
            captureStartTime = nil  // 主 APP 已响应，清除超时计时
            if case .recording = currentState {
                // Already in recording state
            } else {
                Logger.recordingInfo("Detected main app is capturing audio")
                currentState = .recording
            }
            return
        }
        
        // 如果 processingStatus 是 idle 且不在采集，检查状态
        if processingStatus == .idle || processingStatus == .recording {
            if case .transcribing = currentState {
                Logger.keyboardInfo("Resetting from transcribing to idle")
                currentState = .idle
            } else if case .polishing = currentState {
                Logger.keyboardInfo("Resetting from polishing to idle")
                currentState = .idle
            } else if case .recording = currentState {
                // 键盘进入 recording 但主 APP 没有开始采集，检查主 APP 是否活跃
                if !isMainAppActive {
                    // 主 APP 不活跃，需要跳转主 APP
                    Logger.keyboardInfo("Main app not active, opening main app")
                    captureStartTime = nil
                    currentState = .idle
                    triggerSessionActivation()
                } else if let startTime = captureStartTime {
                    // 主 APP 活跃但还没开始采集，检查超时
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed > 1.5 {
                        // 超时，主 APP 没有响应，需要跳转主 APP
                        Logger.keyboardInfo("Capture timeout (\(String(format: "%.1f", elapsed))s), opening main app")
                        captureStartTime = nil
                        currentState = .idle
                        triggerSessionActivation()
                    }
                } else {
                    // 没有开始时间，说明不是我们发起的录制请求，重置
                    Logger.keyboardInfo("Resetting from recording to idle (no capture start time)")
                    currentState = .idle
                }
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
        Logger.keyboardInfo("isMainAppActive: \(isMainAppActive), isCapturing: \(sessionManager.isCapturing)")
        
        // 首先检查完全访问权限
        guard hasOpenAccess else {
            Logger.keyboardError("No Open Access permission, prompting user")
            currentState = .needsOpenAccess
            onNeedsOpenAccess?()
            return
        }
        
        switch currentState {
        case .idle, .error, .needsOpenAccess:
            // 检查主 APP 是否活跃（时间戳在 1 秒内）
            if isMainAppActive {
                Logger.recordingInfo("Main app is active, trying to start capture")
                currentState = .recording
                captureStartTime = Date()  // 记录开始时间，用于超时检测
                requestStartCapturing()
            } else {
                Logger.recordingInfo("Main app not active, opening main app")
                triggerSessionActivation()
            }
        case .recording:
            Logger.recordingInfo("Currently recording, requesting stop")
            captureStartTime = nil  // 清除超时检测
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
