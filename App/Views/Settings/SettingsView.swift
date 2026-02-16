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
                    NavigationLink("Transcription Engine") {
                        TranscriptionEngineSettingsView()
                    }
                    NavigationLink("Background Duration") {
                        BackgroundDurationSettingsView()
                    }
                    NavigationLink("Speech Recognition Language") {
                        SpeechRecognitionLanguageView()
                    }
                    NavigationLink("Whisper Advanced Settings") {
                        WhisperAdvancedSettingsView()
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
