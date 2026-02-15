import SwiftUI

struct BackgroundDurationSettingsView: View {
    @State private var settings = AppSettings.shared
    
    // 预设选项：30秒, 1分钟, 2分钟, 3分钟, 5分钟
    private let durationOptions: [(label: String, seconds: Int)] = [
        ("30 秒", 30),
        ("1 分钟", 60),
        ("2 分钟", 120),
        ("3 分钟", 180),
        ("5 分钟", 300)
    ]
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("后台录音保持")
                        .font(.headline)
                    Text("录音采集结束后，系统录音会继续保持一段时间，避免频繁跳转主 App。超过设定时间后会自动停止。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section("保持时长") {
                ForEach(durationOptions, id: \.seconds) { option in
                    Button {
                        settings.voiceBackgroundDuration = option.seconds
                    } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if settings.voiceBackgroundDuration == option.seconds {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            
            Section {
                HStack {
                    Text("当前设置")
                    Spacer()
                    Text(formatDuration(settings.voiceBackgroundDuration))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("后台保持")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        } else {
            let minutes = seconds / 60
            return "\(minutes) 分钟"
        }
    }
}

#Preview {
    NavigationStack {
        BackgroundDurationSettingsView()
    }
}
