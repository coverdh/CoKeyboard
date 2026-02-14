import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Query(sort: \InputRecord.timestamp, order: .reverse) private var records: [InputRecord]

    var body: some View {
        NavigationStack {
            List(records) { record in
                NavigationLink(destination: HistoryDetailView(record: record)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.polishedText ?? record.originalText)
                            .lineLimit(2)
                            .font(.body)
                        HStack {
                            Text(record.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("V:\(record.whisperTokens) P:\(record.polishTokens)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView("No History", systemImage: "clock", description: Text("Voice inputs will appear here."))
                }
            }
        }
    }
}
