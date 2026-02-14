import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("LLM Configuration") {
                    NavigationLink("API Settings") {
                        LLMSettingsView()
                    }
                }

                Section("Voice") {
                    NavigationLink("Background Duration") {
                        Text("Background Duration Settings")
                    }
                }

                Section("Translation") {
                    NavigationLink("Target Language") {
                        TranslationSettingsView()
                    }
                }

                Section("Vocabulary") {
                    NavigationLink("Custom Vocabulary") {
                        VocabularyView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
