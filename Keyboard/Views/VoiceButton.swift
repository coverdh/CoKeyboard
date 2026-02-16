import UIKit

final class VoiceButton: UIView {
    private let containerView = UIView()
    private let progressFillView = UIView()             // 进度填充层 (在底层)
    private let iconImageView = UIImageView()           // 等待录制时的麦克风图标
    private let waveformView = WaveformView()           // 录制中的动态声波
    private let thinkingLabel = UILabel()
    private let pulseLayer = CAShapeLayer()
    
    var onTap: (() -> Void)?
    
    private var currentState: KeyboardInputState = .idle
    
    // 椭圆尺寸 (宽高比 3:1)
    private let buttonWidth: CGFloat = 180
    private let buttonHeight: CGFloat = 60
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // 脉冲层 (录音时) - 设置锚点为中心
        pulseLayer.opacity = 0
        pulseLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.addSublayer(pulseLayer)
        
        // 容器视图
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = buttonHeight / 2
        containerView.clipsToBounds = true
        containerView.isUserInteractionEnabled = true
        addSubview(containerView)
        
        // 进度填充层 (在容器内作为背景)
        progressFillView.translatesAutoresizingMaskIntoConstraints = false
        progressFillView.backgroundColor = .systemBlue
        progressFillView.isHidden = true
        containerView.addSubview(progressFillView)
        
        // 默认样式：白色底/黑色图标
        updateIdleAppearance()
        
        // 等待录制时的麦克风图标
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .label
        iconImageView.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium))
        containerView.addSubview(iconImageView)
        
        // 声波视图 (录音时显示动态波形)
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.isHidden = true
        waveformView.setBarColor(.white)
        containerView.addSubview(waveformView)
        
        // Thinking 标签 (处理时显示)
        thinkingLabel.translatesAutoresizingMaskIntoConstraints = false
        thinkingLabel.text = "Thinking"
        thinkingLabel.font = .systemFont(ofSize: 16, weight: .medium)
        thinkingLabel.textColor = .white
        thinkingLabel.textAlignment = .center
        thinkingLabel.isHidden = true
        containerView.addSubview(thinkingLabel)
        
        // 点击手势
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        containerView.addGestureRecognizer(tap)
        
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: buttonWidth),
            containerView.heightAnchor.constraint(equalToConstant: buttonHeight),
            
            // 进度填充层 (从左到右填充)
            progressFillView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            progressFillView.topAnchor.constraint(equalTo: containerView.topAnchor),
            progressFillView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),
            
            waveformView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            waveformView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            waveformView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            waveformView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            
            thinkingLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            thinkingLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
        ])
        
        // 进度填充宽度约束 (动态更新)
        progressWidthConstraint = progressFillView.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true
    }
    
    private var progressWidthConstraint: NSLayoutConstraint?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePulseLayerPath()
    }
    
    private func updatePulseLayerPath() {
        // 以按钮中心为锚点设置脉冲层位置
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        pulseLayer.position = center
        pulseLayer.bounds = CGRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight)
        pulseLayer.path = UIBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight),
            cornerRadius: buttonHeight / 2
        ).cgPath
    }
    
    @objc private func handleTap() {
        Logger.keyboardInfo("Voice button tapped, current state: \(stateDescription)")
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        onTap?()
    }
    
    private var stateDescription: String {
        switch currentState {
        case .idle: return "idle"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        case .polishing: return "polishing"
        case .translating: return "translating"
        case .needsSession: return "needsSession"
        case .needsOpenAccess: return "needsOpenAccess"
        case .error(let msg): return "error(\(msg))"
        }
    }
    
    func updateState(_ state: KeyboardInputState) {
        let oldState = stateDescription
        currentState = state
        Logger.stateChange(from: oldState, to: stateDescription)
        
        switch state {
        case .idle, .needsSession:
            showIdleState()
        case .needsOpenAccess:
            showNeedsOpenAccessState()
        case .recording:
            showRecordingState()
        case .transcribing, .polishing, .translating:
            showProcessingState()
        case .error(let message):
            showErrorState(message: message)
        }
    }
    
    // MARK: - State Appearances
    
    private func showIdleState() {
        Logger.keyboardInfo("Showing idle state")
        stopAllAnimations()
        updateIdleAppearance()
        
        iconImageView.isHidden = false
        iconImageView.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium))
        iconImageView.tintColor = .label
        waveformView.isHidden = true
        waveformView.stopAnimating()
        thinkingLabel.isHidden = true
        progressFillView.isHidden = true
        containerView.isUserInteractionEnabled = true
        
        // 重置进度
        updateProgress(0)
    }
    
    private func showRecordingState() {
        Logger.keyboardInfo("Showing recording state")
        stopAllAnimations()
        
        // 保持系统填充色，不改变颜色
        updateIdleAppearance()
        
        iconImageView.isHidden = true
        waveformView.isHidden = false
        waveformView.startAnimating()
        thinkingLabel.isHidden = true
        containerView.isUserInteractionEnabled = true
        
        // 开始脉冲动画
        startPulseAnimation()
    }
    
    private func showProcessingState() {
        Logger.keyboardInfo("Showing processing state (Thinking...)")
        stopAllAnimations()
        
        // 使用原始颜色填充，未完成部分透明
        containerView.backgroundColor = .clear
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.secondarySystemFill.cgColor
        
        // 进度填充层使用原始颜色
        progressFillView.backgroundColor = .secondarySystemFill
        
        iconImageView.isHidden = true
        waveformView.isHidden = true
        waveformView.stopAnimating()
        thinkingLabel.isHidden = false
        progressFillView.isHidden = false
        containerView.isUserInteractionEnabled = false
    }
    
    private func showErrorState(message: String) {
        Logger.keyboardError("Showing error state: \(message)")
        stopAllAnimations()
        updateIdleAppearance()
        
        // 错误时显示警告图标
        iconImageView.isHidden = false
        iconImageView.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium))
        iconImageView.tintColor = .systemOrange
        waveformView.isHidden = true
        thinkingLabel.isHidden = true
        containerView.isUserInteractionEnabled = true
    }
    
    private func showNeedsOpenAccessState() {
        Logger.keyboardInfo("Showing needs open access state")
        stopAllAnimations()
        updateIdleAppearance()
        
        // 显示锁定图标，提示需要开启完全访问
        iconImageView.isHidden = false
        iconImageView.image = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium))
        iconImageView.tintColor = .systemOrange
        waveformView.isHidden = true
        thinkingLabel.isHidden = true
        containerView.isUserInteractionEnabled = true
    }
    
    private func updateIdleAppearance() {
        // 使用轻量级系统填充色，与系统键盘背景融为一体
        containerView.backgroundColor = .secondarySystemFill
        containerView.layer.borderWidth = 0
        containerView.layer.cornerRadius = buttonHeight / 2
    }
    
    // MARK: - Animations
    
    private func startBreathingAnimation() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.05
        scale.duration = 0.8
        scale.autoreverses = true
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        containerView.layer.add(scale, forKey: "breathing")
    }
    
    private func startPulseAnimation() {
        pulseLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.2).cgColor
        pulseLayer.opacity = 1
        
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 1.3
        
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.5
        opacityAnim.toValue = 0.0
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnim, opacityAnim]
        group.duration = 1.0
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulseLayer.add(group, forKey: "pulse")
    }
    
    private func stopAllAnimations() {
        containerView.layer.removeAllAnimations()
        pulseLayer.removeAllAnimations()
        pulseLayer.opacity = 0
        thinkingLabel.layer.removeAllAnimations()
    }
    
    // MARK: - Public Updates
    
    /// 更新处理进度 (0.0-1.0)
    func updateProgress(_ progress: Float) {
        let newWidth = CGFloat(progress) * buttonWidth
        progressWidthConstraint?.constant = newWidth
    }
    
    /// 更新音频电平 (0.0-1.0)
    func updateAudioLevel(_ level: Float) {
        waveformView.updateLevel(level)
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: buttonWidth, height: buttonHeight + 20)
    }
}

// MARK: - Waveform View

final class WaveformView: UIView {
    private var barLayers: [CAShapeLayer] = []
    private let barCount = 5
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 6
    
    // 音频电平历史 (用于平滑显示)
    private var levelHistory: [Float] = [0, 0, 0, 0, 0]
    private var isAnimating = false
    private var displayLink: CADisplayLink?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        for _ in 0..<barCount {
            let bar = CAShapeLayer()
            bar.fillColor = UIColor.white.cgColor
            bar.cornerRadius = barWidth / 2
            layer.addSublayer(bar)
            barLayers.append(bar)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateBarPositions()
    }
    
    private func updateBarPositions() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        var x = (bounds.width - totalWidth) / 2
        let centerY = bounds.height / 2
        let maxHeight = bounds.height * 0.8
        
        for (i, bar) in barLayers.enumerated() {
            let level = CGFloat(levelHistory[i])
            let minHeight = maxHeight * 0.2
            let height = minHeight + (maxHeight - minHeight) * level
            bar.frame = CGRect(x: x, y: centerY - height / 2, width: barWidth, height: height)
            bar.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: bar.frame.size), cornerRadius: barWidth / 2).cgPath
            x += barWidth + barSpacing
        }
    }
    
    /// 更新当前音频电平 (0.0-1.0)
    func updateLevel(_ level: Float) {
        // 将新电平推入历史，移除最旧的
        levelHistory.removeFirst()
        levelHistory.append(level)
        
        // 如果正在动画中，更新条形高度
        if isAnimating {
            updateBarPositions()
        }
    }
    
    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        
        // 使用 displayLink 进行平滑动画
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkUpdate))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func displayLinkUpdate() {
        updateBarPositions()
    }
    
    func stopAnimating() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        
        // 重置电平历史
        levelHistory = [0, 0, 0, 0, 0]
        updateBarPositions()
    }
    
    func setBarColor(_ color: UIColor) {
        for bar in barLayers {
            bar.fillColor = color.cgColor
        }
    }
}
