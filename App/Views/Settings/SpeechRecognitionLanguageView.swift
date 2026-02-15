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
    
    // 辅助语言选项（排除 auto 和当前主语言）
    var secondaryLanguages: [(String?, String, String)] {
        var result: [(String?, String, String)] = [(nil, "None", "无")]
        result += languages.filter { $0.0 != "auto" && $0.0 != settings.speechRecognitionLanguage }
            .map { (Optional($0.0), $0.1, $0.2) }
        return result
    }
    
    var body: some View {
        List {
            // 主语言选择
            Section {
                ForEach(languages, id: \.0) { code, name, nativeName in
                    Button(action: {
                        settings.speechRecognitionLanguage = code
                        // 如果主语言和辅助语言相同，清空辅助语言
                        if settings.speechSecondaryLanguage == code {
                            settings.speechSecondaryLanguage = nil
                        }
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
                Text("Primary Language")
            } footer: {
                Text("主语言用于首次识别，选择“自动检测”可支持混合语言输入。")
            }
            
            // 辅助语言选择
            if settings.speechRecognitionLanguage != "auto" {
                Section {
                    ForEach(secondaryLanguages, id: \.0) { code, name, nativeName in
                        Button(action: {
                            settings.speechSecondaryLanguage = code
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
                                
                                if settings.speechSecondaryLanguage == code {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Secondary Language")
                } footer: {
                    Text("当主语言识别失败时，将自动尝试用辅助语言重新识别。")
                }
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
