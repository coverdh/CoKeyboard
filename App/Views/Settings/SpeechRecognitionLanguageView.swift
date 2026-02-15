import SwiftUI

struct SpeechRecognitionLanguageView: View {
    @State private var settings = AppSettings.shared
    
    let languages = [
        ("auto", "Auto Detect", "Automatically detect language"),
        ("zh", "Chinese", "中文"),
        ("en", "English", "English"),
        ("ja", "Japanese", "日本語"),
        ("ko", "Korean", "한국어"),
        ("fr", "French", "Français"),
        ("de", "German", "Deutsch"),
        ("es", "Spanish", "Español"),
    ]
    
    var body: some View {
        List {
            Section {
                ForEach(languages, id: \.0) { code, name, nativeName in
                    Button(action: {
                        settings.speechRecognitionLanguage = code
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                    .font(.body)
                                Text(nativeName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if settings.speechRecognitionLanguage == code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Select Language")
            } footer: {
                Text("Auto Detect allows mixed Chinese and English input. If recognition is inaccurate, try selecting a specific language.")
            }
        }
        .navigationTitle("Speech Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SpeechRecognitionLanguageView()
    }
}
