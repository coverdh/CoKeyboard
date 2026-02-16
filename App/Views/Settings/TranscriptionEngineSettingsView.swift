import SwiftUI

struct TranscriptionEngineSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var showRestartAlert = false
    
    var body: some View {
        List {
            Section {
                ForEach(TranscriptionEngine.allCases) { engine in
                    EngineOptionRow(
                        engine: engine,
                        isSelected: settings.transcriptionEngine == engine.rawValue,
                        isEnabled: engine.isSupported
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectEngine(engine)
                    }
                }
            } header: {
                Text("选择转写引擎")
            } footer: {
                Text("SpeechAnalyzer 是 iOS 26 引入的系统内置语音识别，无需下载额外模型，响应更快。Whisper 是 OpenAI 开源模型，支持更多语言，离线准确率更高。")
                    .font(.caption)
            }
            
            Section {
                HStack {
                    Text("当前引擎")
                    Spacer()
                    Text(settings.currentTranscriptionEngine.displayName)
                        .foregroundStyle(.secondary)
                }
                
                if settings.currentTranscriptionEngine == .speechAnalyzer {
                    HStack {
                        Text("系统要求")
                        Spacer()
                        Text("iOS 26+")
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("当前状态")
            }
            
            Section {
                Button {
                    settings.resetTranscriptionEngineToDefault()
                    showRestartAlert = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("恢复默认设置")
                    }
                }
                .foregroundStyle(.blue)
            } footer: {
                Text("恢复为系统推荐的默认引擎（iOS 26+ 使用 SpeechAnalyzer，旧版本使用 Whisper）")
                    .font(.caption)
            }
        }
        .navigationTitle("转写引擎")
        .alert("设置已更新", isPresented: $showRestartAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("转写引擎已更改，下次录音时将使用新的引擎。")
        }
    }
    
    private func selectEngine(_ engine: TranscriptionEngine) {
        guard engine.isSupported else {
            return
        }
        
        if settings.transcriptionEngine != engine.rawValue {
            settings.transcriptionEngine = engine.rawValue
            showRestartAlert = true
        }
    }
}

// MARK: - Engine Option Row

struct EngineOptionRow: View {
    let engine: TranscriptionEngine
    let isSelected: Bool
    let isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 选择指示器
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .gray)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(engine.displayName)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                    
                    if !isEnabled {
                        Text("需要 iOS 26+")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                
                Text(engine.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TranscriptionEngineSettingsView()
    }
}
