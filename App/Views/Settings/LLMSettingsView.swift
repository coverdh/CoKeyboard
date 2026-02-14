import SwiftUI

struct LLMSettingsView: View {
    @State private var settings = AppSettings.shared

    private var showBaseURL: Bool {
        settings.llmProvider == "openai" || settings.llmProvider == "custom"
    }

    private var modelPlaceholder: String {
        switch settings.llmProvider {
        case "openai": return "gpt-4o-mini"
        case "bailian": return "qwen-plus"
        default: return "Model name"
        }
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $settings.llmProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Bailian (DashScope)").tag("bailian")
                    Text("Custom").tag("custom")
                }
            }

            Section("API Configuration") {
                SecureField("API Key", text: $settings.llmAPIKey)

                if showBaseURL {
                    TextField("Base URL", text: $settings.llmBaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }

                TextField(modelPlaceholder, text: $settings.llmModel)
                    .autocapitalization(.none)
            }

            if settings.llmProvider == "bailian" {
                Section {
                    Text("Base URL: dashscope.aliyuncs.com")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } footer: {
                    Text("Bailian uses DashScope API with fixed endpoint")
                }
            }
        }
        .navigationTitle("LLM Settings")
    }
}
