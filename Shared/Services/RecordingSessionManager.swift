import Foundation
import AVFoundation

/// 管理跨进程共享的录音会话状态
final class RecordingSessionManager {
    static let shared = RecordingSessionManager()

    private let defaults: UserDefaults?
    
    // Keys
    private let isRecordingKey = "isRecordingActive"
    private let shouldStopKey = "shouldStopRecording"
    private let recordingStartTimeKey = "recordingStartTime"
    private let audioFilePathKey = "recordingAudioFilePath"
    private let sourceAppBundleIDKey = "sourceAppBundleID"
    private let pendingResultKey = "pendingVoiceResult"
    private let processingStatusKey = "processingStatus" // idle, transcribing, polishing, done, error

    private init() {
        defaults = UserDefaults(suiteName: AppConstants.appGroupID)
    }

    // MARK: - Recording State (跨进程共享)

    /// 主App是否正在录音
    var isRecording: Bool {
        get { defaults?.bool(forKey: isRecordingKey) ?? false }
        set {
            defaults?.set(newValue, forKey: isRecordingKey)
            defaults?.synchronize()
        }
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
            let raw = defaults?.string(forKey: processingStatusKey) ?? "idle"
            return ProcessingStatus(rawValue: raw) ?? .idle
        }
        set {
            defaults?.set(newValue.rawValue, forKey: processingStatusKey)
            defaults?.synchronize()
        }
    }

    // MARK: - Source App

    var sourceAppBundleID: String? {
        get { defaults?.string(forKey: sourceAppBundleIDKey) }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: sourceAppBundleIDKey)
            } else {
                defaults?.removeObject(forKey: sourceAppBundleIDKey)
            }
            defaults?.synchronize()
        }
    }

    // MARK: - Pending Result (转写结果传回键盘)

    var pendingResult: String? {
        get { defaults?.string(forKey: pendingResultKey) }
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

    /// 主App调用：开始录音
    func startRecording() {
        shouldStopRecording = false
        isRecording = true
        recordingStartTime = Date()
        processingStatus = .recording
        pendingResult = nil
    }

    /// 主App调用：停止录音
    func stopRecording() {
        isRecording = false
        shouldStopRecording = false
    }

    /// 键盘调用：请求停止录音
    func requestStopRecording() {
        shouldStopRecording = true
    }

    /// 重置所有状态
    func reset() {
        isRecording = false
        shouldStopRecording = false
        recordingStartTime = nil
        audioFilePath = nil
        processingStatus = .idle
        pendingResult = nil
    }

    // MARK: - URL Scheme

    /// 生成跳转主App的URL
    func makeActivationURL(sourceBundleID: String?) -> URL? {
        var components = URLComponents()
        components.scheme = PermissionURLScheme.scheme
        components.host = "start-recording"

        if let bundleID = sourceBundleID {
            components.queryItems = [URLQueryItem(name: "source", value: bundleID)]
        }

        return components.url
    }

    /// 根据bundle ID获取返回URL
    func returnURL(for bundleID: String?) -> URL? {
        guard let bundleID = bundleID else { return nil }

        if let scheme = CommonAppSchemes.schemes[bundleID] {
            return URL(string: scheme)
        }

        let possibleSchemes = [
            bundleID.lowercased().replacingOccurrences(of: ".", with: ""),
            bundleID.components(separatedBy: ".").last?.lowercased()
        ].compactMap { $0 }

        for scheme in possibleSchemes {
            if let url = URL(string: "\(scheme)://") {
                return url
            }
        }

        return nil
    }
}
