import Foundation
import SwiftData

@Model
final class DailyUsage {
    var date: Date
    var inputCount: Int
    var whisperTokens: Int
    var polishTokens: Int

    init(date: Date = .now) {
        self.date = Calendar.current.startOfDay(for: date)
        self.inputCount = 0
        self.whisperTokens = 0
        self.polishTokens = 0
    }
}
