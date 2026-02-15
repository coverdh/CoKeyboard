import SwiftUI
import SwiftData
import AVFoundation

@main
struct CoKeyboardApp: App {
    let modelContainer: ModelContainer
    @StateObject private var recordingService = BackgroundRecordingService.shared
    @State private var showingRecordingOverlay = false
    @State private var sourceBundleID: String?

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
                        sourceBundleID: sourceBundleID,
                        onDismiss: {
                            showingRecordingOverlay = false
                        }
                    )
                    .environmentObject(recordingService)
                    .transition(.opacity)
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

        // Extract source bundle ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let source = queryItems.first(where: { $0.name == "source" })?.value {
            sourceBundleID = source
            RecordingSessionManager.shared.sourceAppBundleID = source
        }

        switch url.host {
        case "start-recording", "activate-session", "request-mic-permission":
            startRecordingAndReturn()
        default:
            break
        }
    }

    private func startRecordingAndReturn() {
        showingRecordingOverlay = true
        
        Task {
            // Request permission first
            let granted = await MicrophonePermission.request()
            guard granted else {
                await MainActor.run {
                    // Show permission denied - don't auto return
                }
                return
            }

            // Start recording
            do {
                try recordingService.startRecording()
                
                // Small delay to ensure recording started
                try? await Task.sleep(for: .milliseconds(300))
                
                // 尝试返回源 App
                await MainActor.run {
                    returnToSourceApp()
                }
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    /// 尝试返回源 App
    private func returnToSourceApp() {
        // 1. 先尝试使用已知的 bundleID
        if let returnURL = RecordingSessionManager.shared.returnURL(for: sourceBundleID) {
            Logger.recordingInfo("Returning to source app via URL: \(returnURL)")
            UIApplication.shared.open(returnURL, options: [:], completionHandler: nil)
            return
        }
        
        // 2. 如果没有 bundleID，显示提示让用户手动切换
        Logger.recordingInfo("No source bundle ID, user needs to switch manually")
        // 录音已开始，用户可以通过系统手势切换回原 App
        // RecordingOverlayView 会显示相应提示
    }
}

// MARK: - Recording Overlay View

struct RecordingOverlayView: View {
    var sourceBundleID: String?
    var onDismiss: () -> Void
    
    @EnvironmentObject var recordingService: BackgroundRecordingService
    @State private var permissionDenied = false
    @State private var showReturnHint = false
    
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
                        
                        if sourceBundleID != nil {
                            Text("点击下方按钮返回键盘")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        } else {
                            Text("请使用系统手势\n从屏幕底部上滑返回键盘")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 8)
                    
                    // 返回按钮（如果有源 App）
                    if sourceBundleID != nil {
                        Button(action: {
                            if let returnURL = sessionManager.returnURL(for: sourceBundleID) {
                                UIApplication.shared.open(returnURL, options: [:], completionHandler: nil)
                            }
                        }) {
                            Label("返回键盘", systemImage: "arrow.uturn.backward")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Capsule())
                        }
                    }
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
            Button(action: {
                if let returnURL = sessionManager.returnURL(for: sourceBundleID) {
                    UIApplication.shared.open(returnURL, options: [:], completionHandler: nil)
                }
                onDismiss()
            }) {
                Label("返回", systemImage: "arrow.uturn.backward")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.8))
                    .clipShape(Capsule())
            }
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
