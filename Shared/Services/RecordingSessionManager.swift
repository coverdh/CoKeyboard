import Foundation
import AVFoundation

/// 管理跨进程共享的录音会话状态
final class RecordingSessionManager {
    static let shared = RecordingSessionManager()

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupID)
    }
    
    // Keys
    private let isRecordingKey = "isRecordingActive"
    private let isCapturingKey = "isCapturingAudio"      // 是否正在采集音频（与系统录音状态区分）
    private let shouldStopKey = "shouldStopRecording"
    private let recordingStartTimeKey = "recordingStartTime"
    private let audioFilePathKey = "recordingAudioFilePath"
    private let pendingResultKey = "pendingVoiceResult"
    private let processingStatusKey = "processingStatus" // idle, transcribing, polishing, done, error
    private let audioLevelKey = "currentAudioLevel"      // 实时音频电平 0.0-1.0
    private let processingProgressKey = "processingProgress" // 处理进度 0.0-1.0
    private let lastCaptureEndTimeKey = "lastCaptureEndTime" // 上次采集结束时间

    private init() {}

    // MARK: - Recording State (跨进程共享)

    /// 主App是否正在录音（系统录音状态）
    var isRecording: Bool {
        get { defaults?.bool(forKey: isRecordingKey) ?? false }
        set {
            defaults?.set(newValue, forKey: isRecordingKey)
            defaults?.synchronize()
        }
    }
    
    /// 是否正在采集音频（用户点击录制后的实际采集状态）
    /// 与 isRecording 区分：isRecording 表示系统录音保持，isCapturing 表示实际在采集音频
    var isCapturing: Bool {
        get { defaults?.bool(forKey: isCapturingKey) ?? false }
        set {
            defaults?.set(newValue, forKey: isCapturingKey)
            defaults?.synchronize()
        }
    }
    
    /// 上次采集结束时间
    var lastCaptureEndTime: Date? {
        get { defaults?.object(forKey: lastCaptureEndTimeKey) as? Date }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: lastCaptureEndTimeKey)
            } else {
                defaults?.removeObject(forKey: lastCaptureEndTimeKey)
            }
            defaults?.synchronize()
        }
    }
    
    /// 检查系统录音是否仍在保持时间内
    /// - Parameter maxIdleSeconds: 最大空闲时间（秒）
    /// - Returns: 如果系统录音仍在保持时间内返回 true
    func isRecordingStillActive(maxIdleSeconds: Int) -> Bool {
        guard isRecording else { return false }
        guard let lastEndTime = lastCaptureEndTime else {
            // 如果没有采集结束时间，说明正在采集中
            return isCapturing
        }
        let idleDuration = Date().timeIntervalSince(lastEndTime)
        return idleDuration < Double(maxIdleSeconds)
    }

    /// 键盘请求停止录音的信号
    var shouldStopRecording: Bool {
        get { defaults?.bool(forKey: shouldStopKey) ?? false }
        set {
            defaults?.set(newValue, forKey: shouldStopKey)
            defaults?.synchronize()
        }
    }

    /// 录音开始时间
    var recordingStartTime: Date? {
        get { defaults?.object(forKey: recordingStartTimeKey) as? Date }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: recordingStartTimeKey)
            } else {
                defaults?.removeObject(forKey: recordingStartTimeKey)
            }
            defaults?.synchronize()
        }
    }

    /// 录音时长（秒）
    var recordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    /// 共享音频文件路径
    var audioFilePath: String? {
        get { defaults?.string(forKey: audioFilePathKey) }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: audioFilePathKey)
            } else {
                defaults?.removeObject(forKey: audioFilePathKey)
            }
            defaults?.synchronize()
        }
    }

    /// 获取共享目录中的音频文件URL
    var sharedAudioURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) else {
            return nil
        }
        // Ensure container directory exists
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        return containerURL.appendingPathComponent("recording.wav")
    }

    // MARK: - Processing Status

    enum ProcessingStatus: String {
        case idle
        case recording
        case transcribing
        case polishing
        case done
        case error
    }

    var processingStatus: ProcessingStatus {
        get {
            defaults?.synchronize()  // 强制同步以获取最新值
            let raw = defaults?.string(forKey: processingStatusKey) ?? "idle"
            return ProcessingStatus(rawValue: raw) ?? .idle
        }
        set {
            defaults?.set(newValue.rawValue, forKey: processingStatusKey)
            defaults?.synchronize()
        }
    }
    
    // MARK: - Audio Level (实时音频电平)
    
    /// 当前音频电平 (0.0-1.0)
    var currentAudioLevel: Float {
        get { defaults?.float(forKey: audioLevelKey) ?? 0.0 }
        set {
            defaults?.set(newValue, forKey: audioLevelKey)
            // 不调用 synchronize，频繁更新时依赖自动同步
        }
    }
    
    // MARK: - Processing Progress (处理进度)
    
    /// 处理进度 (0.0-1.0)
    /// 0.0-0.9: 本地转写进度
    /// 0.9-1.0: 远程润色进度
    var processingProgress: Float {
        get { defaults?.float(forKey: processingProgressKey) ?? 0.0 }
        set {
            defaults?.set(newValue, forKey: processingProgressKey)
            defaults?.synchronize()
        }
    }

    // MARK: - Pending Result (转写结果传回键盘)

    var pendingResult: String? {
        get {
            defaults?.synchronize()  // 强制同步以获取最新值
            return defaults?.string(forKey: pendingResultKey)
        }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: pendingResultKey)
            } else {
                defaults?.removeObject(forKey: pendingResultKey)
            }
            defaults?.synchronize()
        }
    }

    func consumePendingResult() -> String? {
        let result = pendingResult
        pendingResult = nil
        return result
    }

    // MARK: - Session Control

    /// 主App调用：开始录音（系统录音+音频采集）
    func startRecording() {
        shouldStopRecording = false
        isRecording = true
        isCapturing = true
        recordingStartTime = Date()
        lastCaptureEndTime = nil
        processingStatus = .recording
        pendingResult = nil
    }
    
    /// 主App调用：停止音频采集（但保持系统录音）
    func stopCapturing() {
        isCapturing = false
        lastCaptureEndTime = Date()
    }

    /// 主App调用：完全停止录音（系统录音+清理状态）
    func stopRecording() {
        isRecording = false
        isCapturing = false
        shouldStopRecording = false
        lastCaptureEndTime = nil
    }

    /// 键盘调用：请求停止录音
    func requestStopRecording() {
        shouldStopRecording = true
    }

    /// 重置所有状态
    func reset() {
        isRecording = false
        isCapturing = false
        shouldStopRecording = false
        recordingStartTime = nil
        lastCaptureEndTime = nil
        audioFilePath = nil
        processingStatus = .idle
        pendingResult = nil
        currentAudioLevel = 0.0
        processingProgress = 0.0
    }

    // MARK: - URL Scheme

    /// 生成跳转主 App 的 URL
    func makeActivationURL(sourceBundleID: String?) -> URL? {
        var components = URLComponents()
        components.scheme = PermissionURLScheme.scheme
        components.host = "start-recording"
        return components.url
    }
}
