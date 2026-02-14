import Foundation
import SwiftData

final class DataManager: Sendable {
    static let shared = DataManager()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            InputRecord.self,
            DailyUsage.self,
            VocabularyItem.self,
        ])

        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupID
        )

        let storeURL: URL
        if let groupURL {
            storeURL = groupURL.appendingPathComponent("CoKeyboard.store")
        } else {
            storeURL = URL.applicationSupportDirectory.appendingPathComponent("CoKeyboard.store")
        }

        let config = ModelConfiguration(url: storeURL)

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    @MainActor
    func recordInput(original: String, polished: String?, whisperTokens: Int, polishTokens: Int, provider: String?) {
        let record = InputRecord(
            originalText: original,
            polishedText: polished,
            whisperTokens: whisperTokens,
            polishTokens: polishTokens,
            provider: provider
        )
        container.mainContext.insert(record)

        let today = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<DailyUsage>(
            predicate: #Predicate { $0.date == today }
        )

        let existing = try? container.mainContext.fetch(descriptor).first
        if let usage = existing {
            usage.inputCount += 1
            usage.whisperTokens += whisperTokens
            usage.polishTokens += polishTokens
        } else {
            let usage = DailyUsage(date: today)
            usage.inputCount = 1
            usage.whisperTokens = whisperTokens
            usage.polishTokens = polishTokens
            container.mainContext.insert(usage)
        }

        try? container.mainContext.save()
    }
}
