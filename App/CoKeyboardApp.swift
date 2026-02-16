import SwiftUI
import SwiftData
import AVFoundation

@main
struct CoKeyboardApp: App {
    let modelContainer: ModelContainer
    @StateObject private var recordingService = BackgroundRecordingService.shared
    @State private var showingRecordingOverlay = false

    init() {
        modelContainer = DataManager.shared.container
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()

                // Recording overlay (仅在录音时显示，后台处理时不显示遮罩)
                if showingRecordingOverlay && recordingService.isRecording {
                    RecordingOverlayView(
                        onDismiss: {
                            showingRecordingOverlay = false
                        }
                    )
                    .environmentObject(recordingService)
                    .transition(.opacity)
                }
            }
            // 处理完成后自动隐藏遮罩
            .onChange(of: recordingService.isRecording) { oldValue, newValue in
                // 当录音停止且不在录音状态时，隐藏遮罩
                if !newValue {
                    showingRecordingOverlay = false
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showingRecordingOverlay)
            .animation(.easeInOut(duration: 0.3), value: recordingService.isRecording)
            .onOpenURL { url in
                handleURL(url)
            }
        }
        .modelContainer(modelContainer)
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == PermissionURLScheme.scheme else { return }

        switch url.host {
        case "start-recording", "activate-session", "request-mic-permission":
            startRecordingAndReturn()
        default:
            break
        }
    }

    private func startRecordingAndReturn() {
        Task {
            // Request permission first
            let granted = await MicrophonePermission.request()
            guard granted else {
                return
            }

            // Start recording
            do {
                try recordingService.startRecording()
                
                // 设置处理完成后返回上一个 App
                recordingService.setShouldReturnToPreviousApp(true)
                
                // 小延迟确保录音启动，然后返回上一个 App
                try? await Task.sleep(for: .milliseconds(300))
                
                // 使用 suspend 返回上一个 App（用户从哪里来就回哪里）
                await MainActor.run {
                    returnToPreviousApp()
                }
            } catch {
                Logger.recordingError("Failed to start recording: \(error)")
            }
        }
    }
    
    /// 返回上一个 App（利用系统的返回功能）
    private func returnToPreviousApp() {
        Logger.recordingInfo("Returning to previous app via suspend...")
        let selector = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: selector) {
            // UIApplication.shared.perform(selector)
        }
    }
}

// MARK: - Recording Overlay View

struct RecordingOverlayView: View {
    var onDismiss: () -> Void
    
    @EnvironmentObject var recordingService: BackgroundRecordingService
    @State private var permissionDenied = false
    
    private let sessionManager = RecordingSessionManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Status Icon
                statusIcon
                    .font(.system(size: 80))
                    .foregroundStyle(statusColor)

                // Status Text
                Text(statusMessage)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // Recording duration
                if recordingService.isRecording {
                    Text(formatDuration(recordingService.recordingDuration))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(.white)
                    
                    // 显示返回提示
                    VStack(spacing: 8) {
                        Text("录音已在后台运行")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Text("录音完成后将自动返回")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 8)
                }
                
                // Processing status
                if !recordingService.isRecording && sessionManager.processingStatus != .idle {
                    processingStatusView
                }

                // Permission denied
                if permissionDenied {
                    VStack(spacing: 12) {
                        Button(action: {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }) {
                            Label("打开设置", systemImage: "gear")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Capsule())
                        }
                        
                        Button(action: onDismiss) {
                            Text("取消")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .padding(40)
        }
        .onAppear {
            checkPermission()
        }
    }

    private var statusIcon: some View {
        Group {
            if permissionDenied {
                Image(systemName: "mic.slash.circle.fill")
            } else if recordingService.isRecording {
                Image(systemName: "mic.circle.fill")
                    .symbolEffect(.pulse)
            } else {
                switch sessionManager.processingStatus {
                case .transcribing, .polishing:
                    Image(systemName: "waveform.circle.fill")
                        .symbolEffect(.pulse)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                default:
                    Image(systemName: "mic.circle.fill")
                }
            }
        }
    }

    private var statusColor: Color {
        if permissionDenied {
            return .red
        } else if recordingService.isRecording {
            return .red
        } else {
            switch sessionManager.processingStatus {
            case .transcribing, .polishing: return .blue
            case .done: return .green
            case .error: return .red
            default: return .blue
            }
        }
    }

    private var statusMessage: String {
        if permissionDenied {
            return "麦克风权限被拒绝\n请在设置中开启"
        } else if recordingService.isRecording {
            return "录音中..."
        } else {
            switch sessionManager.processingStatus {
            case .transcribing: return "正在转写..."
            case .polishing: return "正在润色..."
            case .done: return "完成!"
            case .error: return "处理失败"
            default: return "启动中..."
            }
        }
    }
    
    @ViewBuilder
    private var processingStatusView: some View {
        if sessionManager.processingStatus == .done {
            Text("处理完成，正在返回...")
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    private func checkPermission() {
        Task {
            let status = MicrophonePermission.current
            await MainActor.run {
                permissionDenied = (status == .denied)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let millis = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, millis)
    }
}
