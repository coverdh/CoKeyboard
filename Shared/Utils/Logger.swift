import Foundation
import os.log

/// 统一日志输出
enum Logger {
    private static let subsystem = "com.cokeyboard"
    
    private static let keyboardLog = OSLog(subsystem: subsystem, category: "Keyboard")
    private static let recordingLog = OSLog(subsystem: subsystem, category: "Recording")
    private static let processingLog = OSLog(subsystem: subsystem, category: "Processing")
    
    // MARK: - Keyboard
    
    static func keyboardInfo(_ message: String) {
        os_log("📱 [Keyboard] %{public}@", log: keyboardLog, type: .info, message)
    }
    
    static func keyboardError(_ message: String, error: Error? = nil) {
        if let error = error {
            os_log("❌ [Keyboard] ERROR: %{public}@ - %{public}@", log: keyboardLog, type: .error, message, error.localizedDescription)
        } else {
            os_log("❌ [Keyboard] ERROR: %{public}@", log: keyboardLog, type: .error, message)
        }
    }
    
    // MARK: - Recording
    
    static func recordingInfo(_ message: String) {
        os_log("🎙️ [Recording] %{public}@", log: recordingLog, type: .info, message)
    }
    
    static func recordingError(_ message: String, error: Error? = nil) {
        if let error = error {
            os_log("❌ [Recording] ERROR: %{public}@ - %{public}@", log: recordingLog, type: .error, message, error.localizedDescription)
        } else {
            os_log("❌ [Recording] ERROR: %{public}@", log: recordingLog, type: .error, message)
        }
    }
    
    // MARK: - Processing
    
    static func processingInfo(_ message: String) {
        os_log("⚙️ [Processing] %{public}@", log: processingLog, type: .info, message)
    }
    
    static func processingError(_ message: String, error: Error? = nil) {
        if let error = error {
            os_log("❌ [Processing] ERROR: %{public}@ - %{public}@", log: processingLog, type: .error, message, error.localizedDescription)
        } else {
            os_log("❌ [Processing] ERROR: %{public}@", log: processingLog, type: .error, message)
        }
    }
    
    // MARK: - State Changes
    
    static func stateChange(from: String, to: String) {
        os_log("🔄 [State] %{public}@ -> %{public}@", log: keyboardLog, type: .info, from, to)
    }
}
