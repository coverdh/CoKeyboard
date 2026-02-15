import Foundation
import AVFoundation
import SwiftData

/// 后台录音服务 - 在主App中运行，监听键盘的停止信号
final class BackgroundRecordingService: ObservableObject {
    static let shared = BackgroundRecordingService()
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var pollTimer: Timer?
    private let sessionManager = RecordingSessionManager.shared
    
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    
    private var durationTimer: Timer?
    
    private init() {
        Logger.recordingInfo("BackgroundRecordingService initialized")
    }
    
    // MARK: - Recording Control
    
    func startRecording() throws {
        Logger.recordingInfo("startRecording() called")
        guard !isRecording else { 
            Logger.recordingInfo("Already recording, ignoring")
            return 
        }
        
        // Configure audio session
        Logger.recordingInfo("Configuring AVAudioSession...")
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            Logger.recordingInfo("AVAudioSession configured successfully")
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
    
    func stopRecording() {
        Logger.recordingInfo("stopRecording() called")
        guard isRecording else { 
            Logger.recordingInfo("Not recording, ignoring")
            return 
        }
        
        // Stop timers
        pollTimer?.invalidate()
        pollTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        Logger.recordingInfo("Timers stopped")
        
        // Stop audio engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        Logger.recordingInfo("AVAudioEngine stopped")
        
        isRecording = false
        let finalDuration = recordingDuration
        recordingDuration = 0
        Logger.recordingInfo("Recording stopped, duration was: \(String(format: "%.1f", finalDuration))s")
        
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
            self?.checkStopSignal()
        }
    }
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration = self?.sessionManager.recordingDuration ?? 0
        }
    }
    
    private func checkStopSignal() {
        guard sessionManager.shouldStopRecording else { return }
        
        Logger.recordingInfo("Stop signal received from keyboard!")
        
        // Keyboard requested stop - process the recording
        Task {
            await processRecording()
        }
    }
    
    // MARK: - Processing
    
    private func processRecording() async {
        Logger.processingInfo("processRecording() started")
        stopRecording()
        
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
