import SwiftUI

struct TranslationSettingsView: View {
    @State private var settings = AppSettings.shared

    private let languages = [
        "English(US)", "English(UK)", "Japanese", "Korean",
        "French", "German", "Spanish", "Portuguese",
        "Chinese(Simplified)", "Chinese(Traditional)"
    ]

    var body: some View {
        Form {
            Section("Target Language") {
                Picker("Language", selection: $settings.targetLanguage) {
                    ForEach(languages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Translation")
    }
}
