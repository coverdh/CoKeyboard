import SwiftUI

struct HistoryDetailView: View {
    let record: InputRecord

    var body: some View {
        List {
            Section("Original (Whisper)") {
                Text(record.originalText)
                    .textSelection(.enabled)
            }

            if let polished = record.polishedText {
                Section("Polished") {
                    Text(polished)
                        .textSelection(.enabled)
                }
            }

            Section("Details") {
                LabeledContent("Time", value: record.timestamp.formatted())
                LabeledContent("Whisper Tokens", value: "\(record.whisperTokens)")
                LabeledContent("Polish Tokens", value: "\(record.polishTokens)")
                if let provider = record.provider {
                    LabeledContent("Provider", value: provider)
                }
            }
        }
        .navigationTitle("Detail")
    }
}
