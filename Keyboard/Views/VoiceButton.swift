import UIKit

final class VoiceButton: UIView {
    private let button = UIButton(type: .system)
    private let pulseLayer = CAShapeLayer()
    private let iconImageView = UIImageView()

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Pulse layer for recording animation
        pulseLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.2).cgColor
        pulseLayer.opacity = 0
        layer.addSublayer(pulseLayer)

        // Main button
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .systemBlue
        button.tintColor = .white
        button.layer.cornerRadius = 50
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        addSubview(button)

        // Icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white
        iconImageView.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
        iconImageView.isUserInteractionEnabled = false
        button.addSubview(iconImageView)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 100),
            button.heightAnchor.constraint(equalToConstant: 100),

            iconImageView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 44),
            iconImageView.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 60
        pulseLayer.path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        ).cgPath
    }

    @objc private func buttonTapped() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        onTap?()
    }

    func updateState(_ state: KeyboardInputState) {
        switch state {
        case .idle:
            stopAllAnimations()
            button.backgroundColor = .systemBlue
            iconImageView.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
            button.isEnabled = true

        case .recording:
            startPulseAnimation()
            button.backgroundColor = .systemRed
            iconImageView.image = UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
            button.isEnabled = true

        case .transcribing, .polishing, .translating:
            stopPulseAnimation()
            startSpinAnimation()
            button.backgroundColor = .systemOrange
            iconImageView.image = UIImage(systemName: "brain.head.profile.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
            button.isEnabled = false

        case .needsSession:
            stopAllAnimations()
            button.backgroundColor = .systemPurple
            iconImageView.image = UIImage(systemName: "arrow.up.forward.app.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
            button.isEnabled = true

        case .error:
            stopAllAnimations()
            button.backgroundColor = .systemGray
            iconImageView.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
            button.isEnabled = true  // Allow retry
        }
    }

    // MARK: - Animations

    private func startPulseAnimation() {
        pulseLayer.opacity = 1
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.8
        scaleAnim.toValue = 1.4
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.6
        opacityAnim.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scaleAnim, opacityAnim]
        group.duration = 1.2
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulseLayer.add(group, forKey: "pulse")
    }

    private func stopPulseAnimation() {
        pulseLayer.removeAnimation(forKey: "pulse")
        pulseLayer.opacity = 0
    }

    private func startSpinAnimation() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 2.0
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        iconImageView.layer.add(rotation, forKey: "spin")
    }

    private func stopAllAnimations() {
        stopPulseAnimation()
        iconImageView.layer.removeAllAnimations()
    }
}
