import Foundation
import AVFoundation
import SwiftData

/// 后台录音服务 - 在主App中运行，监听键盘的停止信号
@MainActor
final class BackgroundRecordingService: ObservableObject {
    static let shared = BackgroundRecordingService()
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var pollTimer: Timer?
    private var idleTimer: Timer?           // 空闲计时器，用于自动停止系统录音
    private let sessionManager = RecordingSessionManager.shared
    
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    
    private var durationTimer: Timer?
    
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
            Logger.recordingInfo("Already recording, ignoring")
            return 
        }
        
        // Configure audio session for background recording
        Logger.recordingInfo("Configuring AVAudioSession for background...")
        let session = AVAudioSession.sharedInstance()
        do {
            // 使用 .playAndRecord 并添加 .mixWithOthers 支持后台录音
            // .duckOthers 让其他音频降低音量而不是完全停止
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
        
        // Get shared audio file URL
        guard let audioURL = sessionManager.sharedAudioURL else {
            Logger.recordingError("No shared container URL available")
            throw RecordingError.noSharedContainer
        }
        Logger.recordingInfo("Audio will be saved to: \(audioURL.path)")
        
        // Remove old file if exists
        if FileManager.default.fileExists(atPath: audioURL.path) {
            try? FileManager.default.removeItem(at: audioURL)
            Logger.recordingInfo("Removed existing audio file")
        }
        
        // Setup audio engine
        Logger.recordingInfo("Setting up AVAudioEngine...")
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Logger.recordingInfo("Input format: \(format.sampleRate)Hz, \(format.channelCount) channels")
        
        do {
            audioFile = try AVAudioFile(forWriting: audioURL, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ])
            Logger.recordingInfo("Audio file created successfully")
        } catch {
            Logger.recordingError("Failed to create audio file", error: error)
            throw error
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            try? self.audioFile?.write(from: buffer)
            
            // 计算音频电平并写入共享状态
            let level = self.calculateAudioLevel(from: buffer)
            self.sessionManager.currentAudioLevel = level
        }
        Logger.recordingInfo("Audio tap installed with level metering")
        
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
        
        // Update shared state
        sessionManager.startRecording()
        sessionManager.audioFilePath = audioURL.path
        Logger.recordingInfo("Shared state updated, isRecording = true")
        
        // Start polling for stop signal
        startPollingForStopSignal()
        
        // Start duration timer
        startDurationTimer()
        
        Logger.recordingInfo("Recording started successfully!")
    }
    
    /// 停止音频采集，但保持系统录音（进入待机状态）
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
    
    /// 停止音频采集的内部实现
    private func stopCapturingInternal() {
        guard isRecording else {
            Logger.recordingInfo("Not recording, ignoring")
            return
        }
        
        // 只停止时长计时器，保留 pollTimer 用于监听新的采集请求
        durationTimer?.invalidate()
        durationTimer = nil
        Logger.recordingInfo("Duration timer stopped, poll timer kept for idle monitoring")
        
        // Stop audio engine (停止采集，但保持 audio session)
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        Logger.recordingInfo("Audio capture stopped, session kept alive")
        
        isRecording = false
        let finalDuration = recordingDuration
        recordingDuration = 0
        Logger.recordingInfo("Capture stopped, duration was: \(String(format: "%.1f", finalDuration))s")
        
        // 清零音频电平
        sessionManager.currentAudioLevel = 0.0
        
        // Update shared state - 停止采集但保持系统录音
        sessionManager.stopCapturing()
        Logger.recordingInfo("Shared state updated, isCapturing = false, isRecording = true")
    }
    
    /// 完全停止录音（系统录音+清理状态）
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
        
        // Stop audio engine and deactivate session
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        
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
        if isRecording {
            if sessionManager.shouldStopRecording {
                Logger.recordingInfo("Stop signal received from keyboard!")
                Task {
                    await processRecording()
                }
            }
            return
        }
        
        // 如果不在采集但系统录音仍在保持（待机状态），检查是否需要重新开始采集
        if !isRecording && sessionManager.isRecording && !sessionManager.isCapturing {
            // 先检查 AVAudioSession 是否仍然有效
            let audioSession = AVAudioSession.sharedInstance()
            guard audioSession.isOtherAudioPlaying == false || audioSession.category == .playAndRecord else {
                // AVAudioSession 可能已被其他 App 抢占，重置状态
                Logger.recordingInfo("AVAudioSession may have been interrupted, resetting state")
                sessionManager.stopRecording()
                return
            }
            
            // 键盘重置了 shouldStopRecording，表示想要开始新的采集
            if !sessionManager.shouldStopRecording {
                // 检查是否有新的采集请求（通过检查 processingStatus）
                if sessionManager.processingStatus == .idle || sessionManager.processingStatus == .done {
                    Logger.recordingInfo("Keyboard requested new capture session")
                    Task {
                        await restartCapturing()
                    }
                }
            }
        }
    }
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration = self?.sessionManager.recordingDuration ?? 0
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
    
    /// 在系统录音保持状态下重新开始采集
    private func restartCapturing() async {
        Logger.recordingInfo("restartCapturing() called")
        
        // 取消空闲计时器
        idleTimer?.invalidate()
        idleTimer = nil
        
        // 先确保 AVAudioSession 仍然有效
        let session = AVAudioSession.sharedInstance()
        do {
            // 重新激活 session，确保它仍然可用
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            Logger.recordingInfo("AVAudioSession reactivated for restart")
        } catch {
            Logger.recordingError("Failed to reactivate AVAudioSession", error: error)
            // 重置状态，让键盘知道需要重新跳转主 App
            sessionManager.stopRecording()
            return
        }
        
        // 获取共享音频文件 URL
        guard let audioURL = sessionManager.sharedAudioURL else {
            Logger.recordingError("No shared container URL available")
            sessionManager.stopRecording()
            return
        }
        
        // 移除旧文件
        if FileManager.default.fileExists(atPath: audioURL.path) {
            try? FileManager.default.removeItem(at: audioURL)
        }
        
        // 设置音频引擎
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        do {
            audioFile = try AVAudioFile(forWriting: audioURL, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ])
        } catch {
            Logger.recordingError("Failed to create audio file", error: error)
            sessionManager.stopRecording()
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            try? self.audioFile?.write(from: buffer)
            
            let level = self.calculateAudioLevel(from: buffer)
            self.sessionManager.currentAudioLevel = level
        }
        
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Logger.recordingError("Failed to start AVAudioEngine", error: error)
            // 启动失败，重置状态
            sessionManager.stopRecording()
            return
        }
        
        self.audioEngine = engine
        self.isRecording = true
        
        // 更新共享状态
        sessionManager.startRecording()
        sessionManager.audioFilePath = audioURL.path
        
        // 启动计时器
        startPollingForStopSignal()
        startDurationTimer()
        
        Logger.recordingInfo("Capture restarted successfully!")
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
