import SwiftUI

struct WhisperAdvancedSettingsView: View {
    @State private var settings = AppSettings.shared
    
    var body: some View {
        List {
            // MARK: - 推理模式
            Section {
                Toggle(isOn: $settings.whisperUseCPUOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CPU Only Mode")
                        Text(settings.whisperUseCPUOnly ? "支持后台转写，但识别质量可能下降" : "识别质量更好，仅支持前台使用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("推理模式")
            } footer: {
                Text("GPU 模式识别更准确，但 iOS 限制后台 App 无法使用 GPU")
            }
            
            // MARK: - 解码参数
            Section {
                // Temperature
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", settings.whisperTemperature))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.whisperTemperature, in: 0...1, step: 0.1)
                
                // Fallback Count
                Stepper(value: $settings.whisperFallbackCount, in: 1...10) {
                    HStack {
                        Text("Fallback Count")
                        Spacer()
                        Text("\(settings.whisperFallbackCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("解码参数")
            } footer: {
                Text("Temperature 越高结果越随机，Fallback 是识别失败时的重试次数")
            }
            
            // MARK: - 阈值设置
            Section {
                Toggle("Suppress Blank", isOn: $settings.whisperSuppressBlank)
                
                Toggle("使用 No Speech 检测", isOn: $settings.whisperUseNoSpeechThreshold)
                
                if settings.whisperUseNoSpeechThreshold {
                    HStack {
                        Text("No Speech Threshold")
                        Spacer()
                        Text(String(format: "%.2f", settings.whisperNoSpeechThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.whisperNoSpeechThreshold, in: 0.1...1.0, step: 0.05)
                }
                
                Toggle("使用 LogProb 阈值", isOn: $settings.whisperUseLogProbThreshold)
                
                if settings.whisperUseLogProbThreshold {
                    HStack {
                        Text("LogProb Threshold")
                        Spacer()
                        Text(String(format: "%.1f", settings.whisperLogProbThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.whisperLogProbThreshold, in: -3.0...0, step: 0.1)
                    
                    HStack {
                        Text("First Token LogProb")
                        Spacer()
                        Text(String(format: "%.1f", settings.whisperFirstTokenLogProbThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.whisperFirstTokenLogProbThreshold, in: -3.0...0, step: 0.1)
                }
                
                Toggle("使用压缩比检测", isOn: $settings.whisperUseCompressionRatioThreshold)
                
                if settings.whisperUseCompressionRatioThreshold {
                    HStack {
                        Text("Compression Ratio")
                        Spacer()
                        Text(String(format: "%.1f", settings.whisperCompressionRatioThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.whisperCompressionRatioThreshold, in: 1.0...5.0, step: 0.1)
                }
            } header: {
                Text("阈值设置")
            } footer: {
                Text("这些阈值用于判断识别结果的质量，关闭可避免误判但可能产生错误输出")
            }
            
            // MARK: - 重置
            Section {
                Button("恢复默认设置") {
                    settings.resetWhisperSettings()
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Whisper 高级设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        WhisperAdvancedSettingsView()
    }
}
