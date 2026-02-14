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
    
    private init() {}
    
    // MARK: - Recording Control
    
    func startRecording() throws {
        guard !isRecording else { return }
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        
        // Get shared audio file URL
        guard let audioURL = sessionManager.sharedAudioURL else {
            throw RecordingError.noSharedContainer
        }
        
        // Remove old file if exists
        try? FileManager.default.removeItem(at: audioURL)
        
        // Setup audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        audioFile = try AVAudioFile(forWriting: audioURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ])
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }
        
        engine.prepare()
        try engine.start()
        
        self.audioEngine = engine
        self.isRecording = true
        
        // Update shared state
        sessionManager.startRecording()
        sessionManager.audioFilePath = audioURL.path
        
        // Start polling for stop signal
        startPollingForStopSignal()
        
        // Start duration timer
        startDurationTimer()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop timers
        pollTimer?.invalidate()
        pollTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        
        // Stop audio engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        
        isRecording = false
        recordingDuration = 0
        
        // Update shared state
        sessionManager.stopRecording()
    }
    
    // MARK: - Background Polling
    
    private func startPollingForStopSignal() {
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
        
        // Keyboard requested stop - process the recording
        Task {
            await processRecording()
        }
    }
    
    // MARK: - Processing
    
    private func processRecording() async {
        stopRecording()
        
        guard let audioURL = sessionManager.sharedAudioURL,
              FileManager.default.fileExists(atPath: audioURL.path) else {
            sessionManager.processingStatus = .error
            return
        }
        
        // Transcribe
        await MainActor.run {
            sessionManager.processingStatus = .transcribing
        }
        
        do {
            let transcription = try await WhisperService.shared.transcribe(audioURL: audioURL)
            
            guard !transcription.text.isEmpty else {
                await MainActor.run {
                    sessionManager.pendingResult = ""
                    sessionManager.processingStatus = .done
                }
                return
            }
            
            // Polish
            await MainActor.run {
                sessionManager.processingStatus = .polishing
            }
            
            let polishService = PolishService()
            let vocabulary = await fetchVocabulary()
            let result = await polishService.polish(text: transcription.text, vocabulary: vocabulary)
            
            // Save result
            await MainActor.run {
                sessionManager.pendingResult = result.text
                sessionManager.processingStatus = .done
                
                // Record to history
                DataManager.shared.recordInput(
                    original: transcription.text,
                    polished: result.wasPolished ? result.text : nil,
                    whisperTokens: transcription.tokenCount,
                    polishTokens: result.polishTokens,
                    provider: result.provider
                )
            }
            
            // Cleanup audio file
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
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
    
    enum RecordingError: Error {
        case noSharedContainer
        case audioSessionFailed
    }
}
