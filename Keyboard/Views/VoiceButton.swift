import UIKit

final class VoiceButton: UIView {
    private let containerView = UIView()
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
        // 脉冲层 (录音时)
        pulseLayer.opacity = 0
        layer.addSublayer(pulseLayer)
        
        // 容器视图
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = buttonHeight / 2
        containerView.clipsToBounds = true
        containerView.isUserInteractionEnabled = true
        addSubview(containerView)
        
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
        thinkingLabel.textColor = .secondaryLabel
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
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePulseLayerPath()
    }
    
    private func updatePulseLayerPath() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        pulseLayer.path = UIBezierPath(
            roundedRect: CGRect(
                x: center.x - buttonWidth / 2,
                y: center.y - buttonHeight / 2,
                width: buttonWidth,
                height: buttonHeight
            ),
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
        containerView.isUserInteractionEnabled = true
    }
    
    private func showRecordingState() {
        Logger.keyboardInfo("Showing recording state")
        stopAllAnimations()
        
        // 红色圆形背景，带脉冲动画
        containerView.backgroundColor = .systemRed
        containerView.layer.borderWidth = 0
        
        iconImageView.isHidden = true
        waveformView.isHidden = false
        waveformView.startAnimating()
        thinkingLabel.isHidden = true
        containerView.isUserInteractionEnabled = true
        
        // 开始缩放动画
        startBreathingAnimation()
        startPulseAnimation()
    }
    
    private func showProcessingState() {
        Logger.keyboardInfo("Showing processing state (Thinking...)")
        stopAllAnimations()
        
        // 透明背景
        containerView.backgroundColor = .clear
        containerView.layer.borderWidth = 0
        
        iconImageView.isHidden = true
        waveformView.isHidden = true
        waveformView.stopAnimating()
        thinkingLabel.isHidden = false
        containerView.isUserInteractionEnabled = false
        
        // Thinking 文字闪烁动画
        startThinkingAnimation()
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
    
    private func updateIdleAppearance() {
        // 使用半透明背景，在毛玻璃效果上更好看
        containerView.backgroundColor = .secondarySystemBackground
        containerView.layer.borderWidth = 0.5
        containerView.layer.borderColor = UIColor.separator.cgColor
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
        pulseLayer.fillColor = UIColor.systemRed.withAlphaComponent(0.3).cgColor
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
    
    private func startThinkingAnimation() {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.3
        opacity.duration = 0.8
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        thinkingLabel.layer.add(opacity, forKey: "thinking")
    }
    
    private func stopAllAnimations() {
        containerView.layer.removeAllAnimations()
        pulseLayer.removeAllAnimations()
        pulseLayer.opacity = 0
        thinkingLabel.layer.removeAllAnimations()
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
        
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        var x = (bounds.width - totalWidth) / 2
        let centerY = bounds.height / 2
        let maxHeight = bounds.height * 0.8
        
        for bar in barLayers {
            let height = maxHeight * 0.4
            bar.frame = CGRect(x: x, y: centerY - height / 2, width: barWidth, height: height)
            bar.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: bar.frame.size), cornerRadius: barWidth / 2).cgPath
            x += barWidth + barSpacing
        }
    }
    
    func startAnimating() {
        let delays: [Double] = [0, 0.1, 0.2, 0.1, 0]
        let maxHeight = bounds.height * 0.8
        
        for (i, bar) in barLayers.enumerated() {
            let anim = CABasicAnimation(keyPath: "bounds.size.height")
            anim.fromValue = maxHeight * 0.3
            anim.toValue = maxHeight
            anim.duration = 0.4
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.beginTime = CACurrentMediaTime() + delays[i]
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(anim, forKey: "wave")
            
            // Also animate position to keep centered
            let posAnim = CABasicAnimation(keyPath: "position.y")
            posAnim.fromValue = bounds.height / 2
            posAnim.toValue = bounds.height / 2
            posAnim.duration = 0.4
            posAnim.autoreverses = true
            posAnim.repeatCount = .infinity
            posAnim.beginTime = CACurrentMediaTime() + delays[i]
            bar.add(posAnim, forKey: "pos")
        }
    }
    
    func stopAnimating() {
        for bar in barLayers {
            bar.removeAllAnimations()
        }
    }
    
    func setBarColor(_ color: UIColor) {
        for bar in barLayers {
            bar.fillColor = color.cgColor
        }
    }
}
