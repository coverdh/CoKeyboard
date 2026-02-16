import Foundation
import AVFoundation
import SwiftData
import UIKit

/// 后台录音服务 - 在主 App 中运行，监听键盘的停止信号
@MainActor
final class BackgroundRecordingService: ObservableObject {
    static let shared = BackgroundRecordingService()
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var pollTimer: Timer?
    private var idleTimer: Timer?           // 空闲计时器，用于自动停止系统录音
    private let sessionManager = RecordingSessionManager.shared
    
    /// 是否需要在处理完成后返回上一个 App
    private var shouldReturnToPreviousApp = false
    
    // 新增：控制是否写入文件的标志
    private var isWritingToFile = false
    
    // 音频格式转换器
    private var audioConverter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?  // 输出文件格式（16kHz 单声道）
    private var useSimpleRecording = true  // 简单录音模式（不做格式转换）
    
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
        let inputFormat = inputNode.outputFormat(forBus: 0)
        Logger.recordingInfo("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        if useSimpleRecording {
            // 简单模式：直接使用设备原始格式，让 WhisperKit 自己处理格式转换
            Logger.recordingInfo("Using simple recording mode (no format conversion)")
            self.outputFormat = nil
            self.audioConverter = nil
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                
                if self.isWritingToFile, let file = self.audioFile {
                    do {
                        try file.write(from: buffer)
                    } catch {
                        Logger.recordingError("Failed to write audio buffer: \(error.localizedDescription)")
                    }
                    let level = self.calculateAudioLevel(from: buffer)
                    self.sessionManager.currentAudioLevel = level
                }
            }
        } else {
            // 转换模式：转换为 16kHz 单声道
            guard let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
                Logger.recordingError("Failed to create Whisper-compatible audio format")
                throw RecordingError.audioSessionFailed
            }
            self.outputFormat = whisperFormat
            Logger.recordingInfo("Output format: 16000Hz, 1 channel, Float32")
            
            guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
                Logger.recordingError("Failed to create audio converter")
                throw RecordingError.audioSessionFailed
            }
            converter.sampleRateConverterQuality = .max
            converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal
            self.audioConverter = converter
            Logger.recordingInfo("Audio converter created successfully with max quality")
            
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                
                if self.isWritingToFile, let file = self.audioFile, let converter = self.audioConverter {
                    let convertedBuffer = self.convertBuffer(buffer, using: converter)
                    if let convertedBuffer = convertedBuffer {
                        do {
                            try file.write(from: convertedBuffer)
                        } catch {
                            Logger.recordingError("Failed to write audio buffer: \(error.localizedDescription)")
                        }
                    }
                    let level = self.calculateAudioLevel(from: buffer)
                    self.sessionManager.currentAudioLevel = level
                }
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
        
        // 发送 Darwin Notify 通知键盘扩展
        DarwinNotify.post(DarwinNotify.recordingStateChanged)
        
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
        
        // 根据录音模式创建音频文件
        let fileSettings: [String: Any]
        if useSimpleRecording {
            // 简单模式：使用设备原始采样率，单声道 16-bit PCM
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            fileSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            Logger.recordingInfo("Creating audio file with format: \(inputFormat.sampleRate)Hz, 1ch, 16-bit PCM (simple mode)")
        } else {
            // 转换模式：16kHz 单声道 16-bit PCM
            fileSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            Logger.recordingInfo("Creating audio file with format: 16000Hz, 1ch, 16-bit PCM (conversion mode)")
        }
        
        do {
            audioFile = try AVAudioFile(forWriting: audioURL, settings: fileSettings)
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
        
        // 发送 Darwin Notify 通知键盘扩展
        DarwinNotify.post(DarwinNotify.recordingStateChanged)
        
        Logger.recordingInfo("Shared state updated, isRecording = false")
    }
    
    // MARK: - Audio Format Conversion
    
    /// 将输入音频 buffer 转换为 WhisperKit 兼容格式（16kHz 单声道）
    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        guard let outputFormat = self.outputFormat else { return nil }
        guard inputBuffer.frameLength > 0 else { return nil }
        
        // 重置 converter 状态，确保每次转换独立
        converter.reset()
        
        // 计算输出 buffer 的帧数
        let inputSampleRate = inputBuffer.format.sampleRate
        let outputSampleRate = outputFormat.sampleRate
        let ratio = outputSampleRate / inputSampleRate
        let outputFrameCapacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio) + 1)
        
        guard outputFrameCapacity > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            return nil
        }
        
        // 使用标志确保 input block 只返回一次数据
        var inputConsumed = false
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        if status == .error {
            if let error = error {
                Logger.recordingError("Audio conversion failed: \(error.localizedDescription)")
            }
            return nil
        }
        
        // 确保输出 buffer 有数据
        guard outputBuffer.frameLength > 0 else {
            return nil
        }
        
        return outputBuffer
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
        
        // Check file size and duration
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? Int64 {
            Logger.processingInfo("Audio file size: \(size) bytes")
            
            // 计算预期时长（16kHz, 16-bit, mono = 32000 bytes/second）
            let expectedDuration = Double(size) / 32000.0
            Logger.processingInfo("Expected audio duration: \(String(format: "%.2f", expectedDuration)) seconds")
            
            // 如果文件太小，可能录音有问题
            if size < 1000 {
                Logger.processingError("Audio file too small, recording may have failed")
            }
        }
        
        // 检查音频文件格式
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let format = audioFile.processingFormat
            let frameCount = audioFile.length
            let duration = Double(frameCount) / format.sampleRate
            Logger.processingInfo("Audio file format: \(format.sampleRate)Hz, \(format.channelCount) channels, \(frameCount) frames")
            Logger.processingInfo("Audio file duration: \(String(format: "%.2f", duration)) seconds")
        } catch {
            Logger.processingError("Failed to read audio file for inspection: \(error.localizedDescription)")
        }
        
        // Transcribe
        Logger.processingInfo("Starting transcription...")
        await MainActor.run {
            sessionManager.processingStatus = .transcribing
            sessionManager.processingProgress = 0.0
        }
        
        do {
            // 根据选择的引擎执行转写
            let settings = AppSettings.shared
            let transcription: TranscriptionResult
            
            if settings.currentTranscriptionEngine == .speechAnalyzer {
                transcription = try await performSpeechAnalyzerTranscription(audioURL: audioURL)
            } else {
                transcription = try await performWhisperTranscription(audioURL: audioURL)
            }
            
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
            
            // 处理完成后返回上一个 App
            if shouldReturnToPreviousApp {
                shouldReturnToPreviousApp = false
                returnToPreviousApp()
            }
            
        } catch let error as WhisperServiceError {
            Logger.processingError("Whisper processing failed: \(error.localizedDescription)", error: error)
            await MainActor.run {
                sessionManager.processingStatus = .error
            }
        } catch let error as SpeechAnalyzerError {
            Logger.processingError("SpeechAnalyzer processing failed: \(error.localizedDescription)", error: error)
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
    
    // MARK: - Transcription Methods
    
    /// 使用 Whisper 进行转写
    private func performWhisperTranscription(audioURL: URL) async throws -> AppTranscriptionResult {
        Logger.processingInfo("Using Whisper engine for transcription")
        
        // 模拟转写进度 (Whisper 不提供真实进度，我们用时间估算)
        let progressTask = Task {
            for i in 1...9 {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    RecordingSessionManager.shared.processingProgress = Float(i) * 0.1
                }
            }
        }
        
        defer { progressTask.cancel() }
        
        let transcription = try await WhisperService.shared.transcribe(audioURL: audioURL)
        Logger.processingInfo("Whisper transcription completed: text=\"\(transcription.text)\", tokenCount=\(transcription.tokenCount)")
        
        return transcription
    }
    
    /// 使用 SpeechAnalyzer 进行转写 (iOS 26+)
    private func performSpeechAnalyzerTranscription(audioURL: URL) async throws -> AppTranscriptionResult {
        Logger.processingInfo("Using SpeechAnalyzer engine for transcription")
        
        guard #available(iOS 26.0, *) else {
            Logger.processingError("SpeechAnalyzer requires iOS 26+")
            throw SpeechAnalyzerError.unsupportedOSVersion
        }
        
        // SpeechAnalyzer 转写速度较快，使用更短的进度更新间隔
        let progressTask = Task {
            for i in 1...5 {
                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run {
                    RecordingSessionManager.shared.processingProgress = Float(i) * 0.15
                }
            }
        }
        
        defer { progressTask.cancel() }
        
        let transcription = try await SpeechAnalyzerService.shared.transcribe(audioURL: audioURL)
        Logger.processingInfo("SpeechAnalyzer transcription completed: text=\"\(transcription.text)\", tokenCount=\(transcription.tokenCount)")
        
        return transcription
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
    
    // MARK: - Return to Previous App
    
    /// 设置处理完成后是否返回上一个 App
    func setShouldReturnToPreviousApp(_ value: Bool) {
        shouldReturnToPreviousApp = value
    }
    
    /// 返回上一个 App（利用系统的返回功能）
    private func returnToPreviousApp() {
        Logger.recordingInfo("Returning to previous app...")
        
        // 方法：使用私有 API 返回上一个应用
        // 这是系统级功能，当用户从其他 App 跳转过来时，系统会记住来源 App
        let selector = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: selector) {
            UIApplication.shared.perform(selector)
            Logger.recordingInfo("Called suspend to return to previous app")
        }
    }
}
