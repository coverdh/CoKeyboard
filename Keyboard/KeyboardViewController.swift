import UIKit

class KeyboardViewController: UIInputViewController {

    private let voiceButton = VoiceButton()
    private let toolbarView = ToolbarView()
    private let tokenCounterView = TokenCounterView()
    private let voiceInputController = VoiceInputController()

    private var deleteTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppSettings.shared.reload()
        // 检查是否有待处理的结果 (从主App返回后)
        voiceInputController.checkPendingResult()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 再次检查，确保结果被处理
        voiceInputController.checkPendingResult()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        tokenCounterView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toolbarView)
        view.addSubview(voiceButton)
        view.addSubview(tokenCounterView)

        NSLayoutConstraint.activate([
            // Toolbar: top-right
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            toolbarView.heightAnchor.constraint(equalToConstant: 36),

            // Voice button: center
            voiceButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            voiceButton.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: 12),

            // Token counter: bottom-right
            tokenCounterView.topAnchor.constraint(equalTo: voiceButton.bottomAnchor, constant: 8),
            tokenCounterView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tokenCounterView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            tokenCounterView.heightAnchor.constraint(equalToConstant: 20),
        ])
        
        // VoiceButton size constraints with lower priority
        let buttonWidth = voiceButton.widthAnchor.constraint(equalToConstant: 140)
        let buttonHeight = voiceButton.heightAnchor.constraint(equalToConstant: 140)
        buttonWidth.priority = .defaultHigh
        buttonHeight.priority = .defaultHigh
        buttonWidth.isActive = true
        buttonHeight.isActive = true

        // Set keyboard height
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 240)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
    }

    // MARK: - Bindings

    private func setupBindings() {
        // Voice button
        voiceButton.onTap = { [weak self] in
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
            DispatchQueue.main.async {
                self?.textDocumentProxy.insertText(text)
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
            if let url = url {
                self?.openURL(url)
            }
        }

        // Toolbar actions
        toolbarView.onTranslate = { [weak self] in
            self?.handleTranslate()
        }
        toolbarView.onAtSign = { [weak self] in
            self?.textDocumentProxy.insertText("@")
        }
        toolbarView.onSpace = { [weak self] in
            self?.textDocumentProxy.insertText(" ")
        }
        toolbarView.onDelete = { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
    }

    // MARK: - Open URL

    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            let selector = NSSelectorFromString("openURL:")
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }

    // MARK: - Translate

    private func handleTranslate() {
        // Read current text from the text field
        let beforeText = textDocumentProxy.documentContextBeforeInput ?? ""
        let afterText = textDocumentProxy.documentContextAfterInput ?? ""
        let fullText = beforeText + afterText

        guard !fullText.isEmpty else { return }

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
