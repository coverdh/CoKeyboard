import UIKit

class KeyboardViewController: UIInputViewController {

    private let voiceButton = VoiceButton()
    private let toolbarView = ToolbarView()
    private let tokenCounterView = TokenCounterView()
    private let voiceInputController = VoiceInputController()

    private var deleteTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.keyboardInfo("KeyboardViewController viewDidLoad")
        setupUI()
        setupBindings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Logger.keyboardInfo("KeyboardViewController viewWillAppear")
        AppSettings.shared.reload()
        // 检查是否有待处理的结果 (从主App返回后)
        voiceInputController.checkPendingResult()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Logger.keyboardInfo("KeyboardViewController viewDidAppear")
        // 再次检查，确保结果被处理
        voiceInputController.checkPendingResult()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Logger.keyboardInfo("KeyboardViewController viewWillDisappear")
        // 键盘收起时重置到等待录制状态
        voiceInputController.resetToIdle()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // 完全透明背景，让系统自动处理键盘外观和模糊效果
        // iOS 系统会自动为键盘扩展添加适当的背景处理
        // 不要手动添加模糊层，否则会与系统效果叠加
        view.backgroundColor = .clear
        
        // 确保inputView也是透明的，与系统toolbar融为一体
        inputView?.backgroundColor = .clear

        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        tokenCounterView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toolbarView)
        view.addSubview(voiceButton)
        view.addSubview(tokenCounterView)

        NSLayoutConstraint.activate([
            // Toolbar: top
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            toolbarView.heightAnchor.constraint(equalToConstant: 32),

            // Voice button: center (椭圆形 3:1)
            voiceButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            voiceButton.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: 16),
            voiceButton.widthAnchor.constraint(equalToConstant: 200),
            voiceButton.heightAnchor.constraint(equalToConstant: 80),

            // Token counter: bottom-right
            tokenCounterView.topAnchor.constraint(equalTo: voiceButton.bottomAnchor, constant: 12),
            tokenCounterView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tokenCounterView.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Set keyboard height - 使用自适应高度，与系统键盘保持一致
        // iOS 26 液态玻璃效果需要键盘高度自适应
        let heightConstraint = view.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        
        Logger.keyboardInfo("UI setup completed")
    }

    // MARK: - Bindings

    private func setupBindings() {
        // Voice button
        voiceButton.onTap = { [weak self] in
            Logger.keyboardInfo("Voice button tap received")
            self?.voiceInputController.toggleRecording()
        }

        // State changes
        voiceInputController.onStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.voiceButton.updateState(state)
            }
        }

        // Text ready
        voiceInputController.onTextReady = { [weak self] text in
            Logger.keyboardInfo("Text ready to insert: \(text.prefix(30))...")
            DispatchQueue.main.async {
                self?.textDocumentProxy.insertText(text)
                Logger.keyboardInfo("Text inserted successfully")
            }
        }

        // Token updates
        voiceInputController.onTokensUpdated = { [weak self] whisper, polish in
            DispatchQueue.main.async {
                self?.tokenCounterView.update(whisperTokens: whisper, polishTokens: polish)
            }
        }
        
        // 音频电平更新
        voiceInputController.onAudioLevelUpdated = { [weak self] level in
            DispatchQueue.main.async {
                self?.voiceButton.updateAudioLevel(level)
            }
        }
        
        // 处理进度更新
        voiceInputController.onProgressUpdated = { [weak self] progress in
            DispatchQueue.main.async {
                self?.voiceButton.updateProgress(progress)
            }
        }

        // 需要激活会话 - 打开主App
        voiceInputController.onNeedsSession = { [weak self] url in
            Logger.keyboardInfo("Need to open main app for recording session")
            if let url = url {
                Logger.keyboardInfo("Opening URL: \(url.absoluteString)")
                self?.openURL(url)
            } else {
                Logger.keyboardError("No URL available for session activation")
            }
        }

        // Toolbar actions
        toolbarView.onDismissKeyboard = { [weak self] in
            Logger.keyboardInfo("Dismiss keyboard tapped")
            self?.handleDismissKeyboard()
        }
        toolbarView.onAtSymbol = { [weak self] in
            Logger.keyboardInfo("@ symbol tapped")
            self?.textDocumentProxy.insertText("@")
        }
        toolbarView.onSpace = { [weak self] in
            self?.textDocumentProxy.insertText(" ")
        }
        toolbarView.onDelete = { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
        
        Logger.keyboardInfo("Bindings setup completed")
    }

    // MARK: - Open URL

    private func openURL(_ url: URL) {
        Logger.keyboardInfo("Attempting to open URL: \(url.absoluteString)")
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                Logger.keyboardInfo("Found UIApplication, opening URL")
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            let selector = NSSelectorFromString("openURL:")
            if r.responds(to: selector) {
                Logger.keyboardInfo("Found responder with openURL:, performing selector")
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
        Logger.keyboardError("Could not find responder to open URL")
    }

    // MARK: - Dismiss Keyboard
    
    private func handleDismissKeyboard() {
        Logger.keyboardInfo("Dismissing keyboard")
        // 使用 UIInputViewController 的 dismissKeyboard() 方法收起键盘
        dismissKeyboard()
    }
}
