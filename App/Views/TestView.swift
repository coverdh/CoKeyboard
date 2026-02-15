import SwiftUI

struct TestView: View {
    @State private var inputText = ""
    @State private var showingKeyboardGuide = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 键盘启用状态
                KeyboardStatusCard()
                
                // 测试输入区域
                VStack(alignment: .leading, spacing: 12) {
                    Text("Test Input")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    TextField("Tap here to test keyboard...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding()
                        .frame(minHeight: 120, alignment: .topLeading)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .focused($isTextFieldFocused)
                }
                
                // 快捷操作
                HStack(spacing: 12) {
                    Button {
                        isTextFieldFocused = true
                    } label: {
                        Label("Focus", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        inputText = ""
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                
                Spacer()
                
                // 提示信息
                VStack(spacing: 8) {
                    Text("Make sure CoKeyboard is enabled in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Open Keyboard Settings") {
                        openKeyboardSettings()
                    }
                    .font(.caption)
                }
            }
            .padding()
            .navigationTitle("Test")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingKeyboardGuide = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .sheet(isPresented: $showingKeyboardGuide) {
                KeyboardGuideView()
            }
        }
    }
    
    private func openKeyboardSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Keyboard Status Card

struct KeyboardStatusCard: View {
    @State private var isKeyboardEnabled = false
    @State private var isFullAccessEnabled = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Keyboard Status")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    checkKeyboardStatus()
                }
                .font(.caption)
            }
            
            HStack(spacing: 20) {
                StatusItem(
                    title: "Enabled",
                    isEnabled: isKeyboardEnabled,
                    icon: "keyboard"
                )
                
                StatusItem(
                    title: "Full Access",
                    isEnabled: isFullAccessEnabled,
                    icon: "lock.open"
                )
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            checkKeyboardStatus()
        }
    }
    
    private func checkKeyboardStatus() {
        // Check if keyboard is enabled
        if let keyboards = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] {
            isKeyboardEnabled = keyboards.contains { $0.contains("com.cokeyboard.keyboard") || $0.contains("CoKeyboardExtension") }
        } else {
            isKeyboardEnabled = false
        }
        
        // Full access check (approximate - check if we can access shared container)
        if let _ = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) {
            isFullAccessEnabled = true
        } else {
            isFullAccessEnabled = false
        }
    }
}

struct StatusItem: View {
    let title: String
    let isEnabled: Bool
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isEnabled ? "\(icon).fill" : icon)
                .font(.title2)
                .foregroundStyle(isEnabled ? .green : .secondary)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isEnabled ? .green : .red)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Keyboard Guide

struct KeyboardGuideView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GuideStep(
                        number: 1,
                        title: "Open Settings",
                        description: "Go to Settings > General > Keyboard > Keyboards"
                    )
                    
                    GuideStep(
                        number: 2,
                        title: "Add New Keyboard",
                        description: "Tap 'Add New Keyboard...' and select 'CoKeyboard'"
                    )
                    
                    GuideStep(
                        number: 3,
                        title: "Enable Full Access",
                        description: "Tap 'CoKeyboard' and enable 'Allow Full Access' for voice input"
                    )
                    
                    GuideStep(
                        number: 4,
                        title: "Switch Keyboard",
                        description: "When typing, tap the globe icon to switch to CoKeyboard"
                    )
                }
                .padding()
            }
            .navigationTitle("Setup Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GuideStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    TestView()
}
