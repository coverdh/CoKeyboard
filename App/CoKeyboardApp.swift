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

                // Recording overlay (shown when recording in background)
                if showingRecordingOverlay || recordingService.isRecording {
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
                
                // Return to source app
                if let returnURL = RecordingSessionManager.shared.returnURL(for: sourceBundleID) {
                    await MainActor.run {
                        UIApplication.shared.open(returnURL, options: [:], completionHandler: nil)
                    }
                }
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
}

// MARK: - Recording Overlay View

struct RecordingOverlayView: View {
    var sourceBundleID: String?
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
                    
                    Text("Recording in background...\nReturn to keyboard to stop")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        if let returnURL = sessionManager.returnURL(for: sourceBundleID) {
                            UIApplication.shared.open(returnURL, options: [:], completionHandler: nil)
                        }
                    }) {
                        Label("Return to App", systemImage: "arrow.uturn.backward")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.8))
                            .clipShape(Capsule())
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
                            Label("Open Settings", systemImage: "gear")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Capsule())
                        }

                        Button(action: onDismiss) {
                            Text("Cancel")
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
            return "Microphone access denied.\nPlease enable in Settings."
        } else if recordingService.isRecording {
            return "Recording..."
        } else {
            switch sessionManager.processingStatus {
            case .transcribing: return "Transcribing..."
            case .polishing: return "Polishing..."
            case .done: return "Done!"
            case .error: return "Processing failed"
            default: return "Starting..."
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
                Label("Return to App", systemImage: "arrow.uturn.backward")
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
