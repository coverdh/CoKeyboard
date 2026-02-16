import SwiftUI

struct SpeechRecognitionLanguageView: View {
    @State private var settings = AppSettings.shared
    
    let languages = [
        ("auto", "Auto Detect", "自动检测"),
        ("zh", "Chinese", "简体中文"),
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
                Text("Recognition Language")
            } footer: {
                Text("选择“自动检测”可支持混合语言输入。")
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
