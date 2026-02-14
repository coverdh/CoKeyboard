import Foundation
import SwiftData

@Model
final class InputRecord {
    var id: UUID
    var timestamp: Date
    var originalText: String
    var polishedText: String?
    var whisperTokens: Int
    var polishTokens: Int
    var provider: String?

    init(
        originalText: String,
        polishedText: String? = nil,
        whisperTokens: Int = 0,
        polishTokens: Int = 0,
        provider: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.originalText = originalText
        self.polishedText = polishedText
        self.whisperTokens = whisperTokens
        self.polishTokens = polishTokens
        self.provider = provider
    }
}
