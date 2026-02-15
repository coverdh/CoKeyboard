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

    // MARK: - UI Setup

    private func setupUI() {
        // 使用透明背景，让系统处理键盘背景色
        // 添加毛玻璃效果背景，与系统键盘一致
        view.backgroundColor = .clear
        
        // 添加模糊背景
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)
        view.sendSubviewToBack(blurView)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

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

        // Set keyboard height (smaller now with new design)
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 180)
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
        toolbarView.onSettings = { [weak self] in
            Logger.keyboardInfo("Settings tapped - opening main app settings")
            if let url = URL(string: "\(PermissionURLScheme.scheme)://settings") {
                self?.openURL(url)
            }
        }
        toolbarView.onTranslate = { [weak self] in
            self?.handleTranslate()
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

    // MARK: - Translate

    private func handleTranslate() {
        Logger.keyboardInfo("handleTranslate called")
        // Read current text from the text field
        let beforeText = textDocumentProxy.documentContextBeforeInput ?? ""
        let afterText = textDocumentProxy.documentContextAfterInput ?? ""
        let fullText = beforeText + afterText

        guard !fullText.isEmpty else { 
            Logger.keyboardInfo("No text to translate")
            return 
        }
        
        Logger.keyboardInfo("Translating text: \(fullText.prefix(30))...")

        // Delete existing text
        for _ in 0..<afterText.count {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
        }
        for _ in 0..<(beforeText.count + afterText.count) {
            textDocumentProxy.deleteBackward()
        }

        voiceInputController.translate(text: fullText)
    }
}
