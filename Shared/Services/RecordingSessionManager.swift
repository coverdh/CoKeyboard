import Foundation
import AVFoundation

/// 管理跨进程共享的录音会话状态
final class RecordingSessionManager {
    static let shared = RecordingSessionManager()

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupID)
    }
    
    // Keys
    private let lastActiveTimeKey = "lastActiveTime"       // 主 APP 活跃时间戳（每200ms更新）
    private let shouldStopKey = "shouldStopRecording"
    private let recordingStartTimeKey = "recordingStartTime"
    private let audioFilePathKey = "recordingAudioFilePath"
    private let pendingResultKey = "pendingVoiceResult"
    private let processingStatusKey = "processingStatus" // idle, transcribing, polishing, done, error
    private let audioLevelKey = "currentAudioLevel"      // 实时音频电平 0.0-1.0
    private let processingProgressKey = "processingProgress" // 处理进度 0.0-1.0

    private init() {}

    // MARK: - Recording State (基于时间戳的状态检测)

    /// 主 APP 最后活跃时间（每 200ms 更新一次）
    var lastActiveTime: Date? {
        get {
            defaults?.synchronize()
            return defaults?.object(forKey: lastActiveTimeKey) as? Date
        }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: lastActiveTimeKey)
            } else {
                defaults?.removeObject(forKey: lastActiveTimeKey)
            }
            // 不调用 synchronize，高频更新时依赖自动同步
        }
    }
    
    /// 更新活跃时间戳（主 APP 每 200ms 调用）
    func updateActiveTime() {
        lastActiveTime = Date()
    }
    
    /// 检查主 APP 是否活跃（时间戳在 1 秒内）
    var isMainAppActive: Bool {
        guard let lastActive = lastActiveTime else { return false }
        return Date().timeIntervalSince(lastActive) < 1.0
    }
    
    /// 检查是否正在录音（processingStatus 为 recording 且主 APP 活跃）
    var isRecording: Bool {
        return processingStatus == .recording && isMainAppActive
    }
    
    /// 检查是否正在采集音频（有音频电平更新且主 APP 活跃）
    var isCapturing: Bool {
        return isMainAppActive && currentAudioLevel > 0
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
        recordingStartTime = Date()
        processingStatus = .recording
        pendingResult = nil
        updateActiveTime()  // 立即更新时间戳
    }
    
    /// 主App调用：停止音频采集（但保持系统录音待机）
    func stopCapturing() {
        currentAudioLevel = 0.0
        // processingStatus 保持 .recording，表示系统录音仍在运行
        // 时间戳继续更新，表示主 APP 仍然活跃
    }

    /// 主App调用：完全停止录音（系统录音+清理状态）
    func stopRecording() {
        shouldStopRecording = false
        currentAudioLevel = 0.0
        processingStatus = .idle
        lastActiveTime = nil  // 清除时间戳，表示不再活跃
    }

    /// 键盘调用：请求停止录音
    func requestStopRecording() {
        shouldStopRecording = true
    }

    /// 重置所有状态
    func reset() {
        shouldStopRecording = false
        recordingStartTime = nil
        audioFilePath = nil
        processingStatus = .idle
        pendingResult = nil
        currentAudioLevel = 0.0
        processingProgress = 0.0
        lastActiveTime = nil
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
