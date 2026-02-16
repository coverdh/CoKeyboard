import Foundation

enum AppConstants {
    static let appGroupID = "group.com.cover.CoKeyboard"
    static let defaultTargetLanguage = "English(US)"
    static let defaultVoiceBackgroundDuration = 60
    static let llmTimeoutSeconds: TimeInterval = 10
    static let llmMaxRetries = 1

    // Shared keys for App Groups
    static let pendingResultKey = "pendingVoiceResult"
    static let pendingResultTimestampKey = "pendingVoiceResultTimestamp"
    static let sourceAppURLKey = "sourceAppURL"
}
