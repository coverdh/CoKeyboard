import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query(sort: \DailyUsage.date, order: .reverse) private var usages: [DailyUsage]

    private var last7Days: [DailyUsage] {
        Array(usages.prefix(7).reversed())
    }

    private var totalInputs: Int {
        usages.reduce(0) { $0 + $1.inputCount }
    }

    private var totalWhisperTokens: Int {
        usages.reduce(0) { $0 + $1.whisperTokens }
    }

    private var totalPolishTokens: Int {
        usages.reduce(0) { $0 + $1.polishTokens }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    LabeledContent("Total Inputs", value: "\(totalInputs)")
                    LabeledContent("Whisper Tokens", value: "\(totalWhisperTokens)")
                    LabeledContent("Polish Tokens", value: "\(totalPolishTokens)")
                }

                Section("Last 7 Days") {
                    if last7Days.isEmpty {
                        Text("No data yet")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(last7Days) { usage in
                            BarMark(
                                x: .value("Date", usage.date, unit: .day),
                                y: .value("Inputs", usage.inputCount)
                            )
                            .foregroundStyle(.blue)
                        }
                        .frame(height: 200)
                    }
                }

                Section("Token Usage (7 Days)") {
                    if !last7Days.isEmpty {
                        Chart(last7Days) { usage in
                            LineMark(
                                x: .value("Date", usage.date, unit: .day),
                                y: .value("Tokens", usage.whisperTokens)
                            )
                            .foregroundStyle(by: .value("Type", "Whisper"))

                            LineMark(
                                x: .value("Date", usage.date, unit: .day),
                                y: .value("Tokens", usage.polishTokens)
                            )
                            .foregroundStyle(by: .value("Type", "Polish"))
                        }
                        .frame(height: 200)
                    }
                }
            }
            .navigationTitle("Statistics")
        }
    }
}
