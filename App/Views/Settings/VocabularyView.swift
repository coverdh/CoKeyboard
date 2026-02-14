import SwiftUI
import SwiftData

struct VocabularyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyItem.createdAt, order: .reverse) private var items: [VocabularyItem]
    @State private var showingAddSheet = false
    @State private var newTerm = ""
    @State private var newContext = ""

    var body: some View {
        List {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.term)
                        .font(.headline)
                    if let context = item.context, !context.isEmpty {
                        Text(context)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteItems)
        }
        .navigationTitle("Vocabulary")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                Form {
                    TextField("Term", text: $newTerm)
                    TextField("Context (optional)", text: $newContext)
                }
                .navigationTitle("Add Vocabulary")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let item = VocabularyItem(
                                term: newTerm,
                                context: newContext.isEmpty ? nil : newContext
                            )
                            modelContext.insert(item)
                            newTerm = ""
                            newContext = ""
                            showingAddSheet = false
                        }
                        .disabled(newTerm.isEmpty)
                    }
                }
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }
}
