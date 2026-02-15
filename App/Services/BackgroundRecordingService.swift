import Foundation
import AVFoundation
import SwiftData

/// 后台录音服务 - 在主 App 中运行，监听键盘的停止信号
@MainActor
final class BackgroundRecordingService: ObservableObject {
    static let shared = BackgroundRecordingService()
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var pollTimer: Timer?
    private var idleTimer: Timer?           // 空闲计时器，用于自动停止系统录音
    private let sessionManager = RecordingSessionManager.shared
    
    // 新增：控制是否写入文件的标志
    private var isWritingToFile = false
    
    @Published var isRecording = false      // AVAudioEngine 是否运行
    @Published var isCapturing = false      // 是否正在采集（写入文件）
    @Published var recordingDuration: TimeInterval = 0
    
    private var durationTimer: Timer?
    private var captureStartTime: Date?     // 采集开始时间
    
    private init() {
        Logger.recordingInfo("BackgroundRecordingService initialized")
        setupAudioSessionNotifications()
    }
    
    // MARK: - Audio Session Notifications
    
    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            Logger.recordingInfo("Audio session interrupted - pausing recording")
            // 系统中断了音频会话（如来电），需要处理
            if isRecording {
                // 保存当前文件，停止采集
                stopCapturingInternal()
            }
        case .ended:
            Logger.recordingInfo("Audio session interruption ended")
            // 中断结束，可以尝试恢复
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    Logger.recordingInfo("Audio session can resume")
                    // 不自动恢复，让用户重新点击录音按钮
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            Logger.recordingInfo("Audio route changed - device unavailable")
            // 耳机拔出等情况，可能需要停止录音
        case .newDeviceAvailable:
            Logger.recordingInfo("Audio route changed - new device available")
        default:
            break
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording() throws {
        Logger.recordingInfo("startRecording() called")
        guard !isRecording else { 
            // 如果已经在录音，只需要开始采集
            Logger.recordingInfo("Already recording, just start capturing")
            startCapturing()
            return 
        }
        
        // Configure audio session for background recording
        Logger.recordingInfo("Configuring AVAudioSession for background...")
        let session = AVAudioSession.sharedInstance()
        do {
            // 使用 .playAndRecord 并添加 .mixWithOthers 支持后台录音
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            Logger.recordingInfo("AVAudioSession configured successfully for background")
        } catch {
            Logger.recordingError("Failed to configure AVAudioSession", error: error)
            throw error
        }
        
        // Setup audio engine
        Logger.recordingInfo("Setting up AVAudioEngine...")
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Logger.recordingInfo("Input format: \(format.sampleRate)Hz, \(format.channelCount) channels")
        
        // 安装 audio tap，但只有在 isWritingToFile=true 时才写入文件
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // 只有在采集模式时才写入文件
            if self.isWritingToFile, let file = self.audioFile {
                do {
                    try file.write(from: buffer)
                } catch {
                    Logger.recordingError("Failed to write audio buffer: \(error.localizedDescription)")
                }
                // 计算音频电平
                let level = self.calculateAudioLevel(from: buffer)
                self.sessionManager.currentAudioLevel = level
            }
        }
        Logger.recordingInfo("Audio tap installed")
        
        engine.prepare()
        do {
            try engine.start()
            Logger.recordingInfo("AVAudioEngine started successfully")
        } catch {
            Logger.recordingError("Failed to start AVAudioEngine", error: error)
            throw error
        }
        
        self.audioEngine = engine
        self.isRecording = true
        
        // Start polling for signals
        startPollingForStopSignal()
        
        // 立即开始采集
        startCapturing()
        
        Logger.recordingInfo("Recording started successfully!")
    }
    
    /// 开始采集（写入文件）
    private func startCapturing() {
        guard isRecording else {
            Logger.recordingInfo("Cannot start capturing - not recording")
            return
        }
        
        guard let engine = audioEngine else {
            Logger.recordingError("AudioEngine is nil")
            return
        }
        
        // 取消空闲计时器
        idleTimer?.invalidate()
        idleTimer = nil
        
        // 获取共享音频文件 URL
        guard let audioURL = sessionManager.sharedAudioURL else {
            Logger.recordingError("No shared container URL available")
            return
        }
        
        // 移除旧文件
        if FileManager.default.fileExists(atPath: audioURL.path) {
            try? FileManager.default.removeItem(at: audioURL)
        }
        
        // 使用与 audio tap 相同的格式创建文件（关键！）
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        Logger.recordingInfo("Creating audio file with format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch, \(inputFormat.commonFormat.rawValue)")
        
        do {
            // 使用 inputNode 的输出格式创建文件，确保格式匹配
            audioFile = try AVAudioFile(forWriting: audioURL, settings: inputFormat.settings)
            Logger.recordingInfo("Audio file created successfully")
        } catch {
            Logger.recordingError("Failed to create audio file: \(error.localizedDescription)", error: error)
            return
        }
        
        // 开始写入文件
        isWritingToFile = true
        isCapturing = true
        captureStartTime = Date()
        
        // 更新共享状态
        sessionManager.startRecording()
        sessionManager.audioFilePath = audioURL.path
        
        // 启动时长计时器
        startDurationTimer()
        
        Logger.recordingInfo("Capturing started")
    }
    
    /// 停止音频采集，保持 AVAudioEngine 运行（进入待机状态）
    func stopCapturing() {
        Logger.recordingInfo("stopCapturing() called - entering idle state")
        stopCapturingInternal()
        // 启动空闲计时器，自动停止系统录音
        startIdleTimer()
    }
    
    /// 停止音频采集用于处理（不启动 idle timer，由 processRecording 完成后手动启动）
    private func stopCapturingForProcessing() {
        Logger.recordingInfo("stopCapturingForProcessing() called - will process audio")
        stopCapturingInternal()
        // 不启动 idle timer，由 processRecording 完成后启动
    }
    
    /// 停止音频采集的内部实现（保持 AVAudioEngine 运行）
    private func stopCapturingInternal() {
        guard isCapturing else {
            Logger.recordingInfo("Not capturing, ignoring")
            return
        }
        
        // 停止写入文件，但保持 AVAudioEngine 运行
        isWritingToFile = false
        isCapturing = false
        
        // 关闭音频文件
        audioFile = nil
        
        // 停止时长计时器
        durationTimer?.invalidate()
        durationTimer = nil
        
        let finalDuration = recordingDuration
        recordingDuration = 0
        Logger.recordingInfo("Capture stopped, duration was: \(String(format: "%.1f", finalDuration))s, engine still running")
        
        // 清零音频电平
        sessionManager.currentAudioLevel = 0.0
        
        // 更新共享状态 - 停止采集但保持系统录音
        sessionManager.stopCapturing()
        Logger.recordingInfo("Shared state updated, isCapturing = false, isRecording = true")
    }
    
    /// 完全停止录音（AVAudioEngine + 清理状态）
    func stopRecording() {
        Logger.recordingInfo("stopRecording() called - full stop")
        
        // Stop all timers
        pollTimer?.invalidate()
        pollTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        Logger.recordingInfo("All timers stopped")
        
        // 停止写入文件
        isWritingToFile = false
        isCapturing = false
        audioFile = nil
        
        // Stop audio engine and deactivate session
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            Logger.recordingInfo("AVAudioSession deactivated")
        } catch {
            Logger.recordingError("Failed to deactivate AVAudioSession", error: error)
        }
        
        isRecording = false
        recordingDuration = 0
        
        // 清零音频电平
        sessionManager.currentAudioLevel = 0.0
        
        // Update shared state
        sessionManager.stopRecording()
        Logger.recordingInfo("Shared state updated, isRecording = false")
    }
    
    // MARK: - Audio Level Calculation
    
    /// 计算音频缓冲区的电平 (RMS)
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        
        // 计算 RMS (均方根)
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        
        // 将 RMS 转换为 0-1 范围，并应用对数缩放使其更线性
        // 典型的语音 RMS 在 0.01-0.3 范围
        let normalizedLevel = min(1.0, max(0.0, rms * 3.0))
        return normalizedLevel
    }
    
    // MARK: - Background Polling
    
    private func startPollingForStopSignal() {
        Logger.recordingInfo("Starting stop signal polling (interval: 0.3s)")
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkSignals()
        }
    }
    
    /// 检查键盘发来的信号（停止或重新开始采集）
    private func checkSignals() {
        let sessionManager = RecordingSessionManager.shared
        
        // 如果正在采集，检查是否需要停止
        if isCapturing {
            if sessionManager.shouldStopRecording {
                Logger.recordingInfo("Stop signal received from keyboard!")
                Task {
                    await processRecording()
                }
            }
            return
        }
        
        // 如果 AVAudioEngine 运行中但不在采集（待机状态），检查是否需要重新开始采集
        if isRecording && !isCapturing {
            // 键盘重置了 shouldStopRecording，表示想要开始新的采集
            if !sessionManager.shouldStopRecording {
                // 检查是否有新的采集请求（通过检查 processingStatus）
                if sessionManager.processingStatus == .idle || sessionManager.processingStatus == .done {
                    Logger.recordingInfo("Keyboard requested new capture session")
                    // 直接开始采集，不需要重新创建 AVAudioEngine
                    startCapturing()
                }
            }
        }
    }
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.captureStartTime else { return }
            self.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    // MARK: - Idle Timer (自动停止系统录音)
    
    private func startIdleTimer() {
        let settings = AppSettings.shared
        let duration = settings.voiceBackgroundDuration
        
        Logger.recordingInfo("Starting idle timer for \(duration)s")
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(duration), repeats: false) { [weak self] _ in
            self?.idleTimerFired()
        }
    }
    
    private func idleTimerFired() {
        Logger.recordingInfo("Idle timer fired - auto stopping system recording")
        stopRecording()
    }
    
    // MARK: - Processing
    
    private func processRecording() async {
        Logger.processingInfo("processRecording() started")
        stopCapturingForProcessing()  // 不启动 idle timer
        
        defer {
            // 处理完成后启动 idle timer
            Task { @MainActor in
                startIdleTimer()
            }
        }
        
        guard let audioURL = sessionManager.sharedAudioURL else {
            Logger.processingError("No shared audio URL")
            sessionManager.processingStatus = .error
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Logger.processingError("Audio file does not exist at: \(audioURL.path)")
            sessionManager.processingStatus = .error
            return
        }
        
        // Check file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? Int64 {
            Logger.processingInfo("Audio file size: \(size) bytes")
        }
        
        // Transcribe
        Logger.processingInfo("Starting transcription...")
        await MainActor.run {
            sessionManager.processingStatus = .transcribing
            sessionManager.processingProgress = 0.0
        }
        
        do {
            // 模拟转写进度 (Whisper 不提供真实进度，我们用时间估算)
            let progressTask = Task {
                for i in 1...9 {
                    try? await Task.sleep(for: .milliseconds(300))
                    await MainActor.run {
                        sessionManager.processingProgress = Float(i) * 0.1  // 0.1 -> 0.9
                    }
                }
            }
            
            let transcription = try await WhisperService.shared.transcribe(audioURL: audioURL)
            progressTask.cancel()
            
            await MainActor.run {
                sessionManager.processingProgress = 0.9  // 转写完成，进度 90%
            }
            
            Logger.processingInfo("Transcription completed: \"\(transcription.text.prefix(50))...\" (\(transcription.tokenCount) tokens)")
            
            guard !transcription.text.isEmpty else {
                Logger.processingInfo("Transcription was empty, setting result to empty")
                await MainActor.run {
                    sessionManager.pendingResult = ""
                    sessionManager.processingStatus = .done
                    sessionManager.processingProgress = 1.0
                }
                return
            }
            
            // Polish
            Logger.processingInfo("Starting polishing...")
            await MainActor.run {
                sessionManager.processingStatus = .polishing
            }
            
            let polishService = PolishService()
            let vocabulary = await fetchVocabulary()
            Logger.processingInfo("Vocabulary items: \(vocabulary.count)")
            
            let result = await polishService.polish(text: transcription.text, vocabulary: vocabulary)
            Logger.processingInfo("Polishing completed: \"\(result.text.prefix(50))...\" (wasPolished: \(result.wasPolished))")
            
            // Save result
            await MainActor.run {
                sessionManager.pendingResult = result.text
                sessionManager.processingStatus = .done
                sessionManager.processingProgress = 1.0
                Logger.processingInfo("Result saved to pendingResult")
                
                // Record to history
                DataManager.shared.recordInput(
                    original: transcription.text,
                    polished: result.wasPolished ? result.text : nil,
                    whisperTokens: transcription.tokenCount,
                    polishTokens: result.polishTokens,
                    provider: result.provider
                )
                Logger.processingInfo("History recorded")
            }
            
            // Cleanup audio file
            try? FileManager.default.removeItem(at: audioURL)
            Logger.processingInfo("Audio file cleaned up")
            
        } catch let error as WhisperServiceError {
            Logger.processingError("Whisper processing failed: \(error.localizedDescription)", error: error)
            await MainActor.run {
                sessionManager.processingStatus = .error
            }
        } catch {
            Logger.processingError("Processing failed with unknown error", error: error)
            await MainActor.run {
                sessionManager.processingStatus = .error
            }
        }
    }
    
    @MainActor
    private func fetchVocabulary() -> [VocabularyItem] {
        let descriptor = FetchDescriptor<VocabularyItem>()
        return (try? DataManager.shared.container.mainContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Errors
    
    enum RecordingError: Error, LocalizedError {
        case noSharedContainer
        case audioSessionFailed
        
        var errorDescription: String? {
            switch self {
            case .noSharedContainer: return "No shared container available"
            case .audioSessionFailed: return "Audio session configuration failed"
            }
        }
    }
}
