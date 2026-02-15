import UIKit

final class ToolbarView: UIView {
    var onDismissKeyboard: (() -> Void)?
    var onAtSymbol: (() -> Void)?
    var onSpace: (() -> Void)?
    var onDelete: (() -> Void)?
    
    private let leftStack = UIStackView()
    private let rightStack = UIStackView()
    
    // 小按钮尺寸
    private let buttonSize: CGFloat = 32
    
    // 长按连续操作相关
    private var longPressTimer: Timer?
    private var longPressAction: (() -> Void)?
    private var repeatInterval: TimeInterval = 0.1
    private var initialDelay: TimeInterval = 0.4
    private var isInitialDelayPassed = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // 左侧收起键盘按钮
        leftStack.axis = .horizontal
        leftStack.spacing = 8
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)
        
        // 右侧功能按钮
        rightStack.axis = .horizontal
        rightStack.spacing = 8
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)
        
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        
        // 左侧：收起键盘按钮
        let dismissBtn = createIconButton(icon: "keyboard.chevron.compact.down", action: #selector(dismissKeyboardTapped))
        leftStack.addArrangedSubview(dismissBtn)
        
        // 右侧功能按钮：@（普通按钮）、空格（支持长按）、删除（支持长按）
        let atBtn = createIconButton(icon: "at", action: #selector(atSymbolTapped))
        rightStack.addArrangedSubview(atBtn)
        
        // 空格按钮 - 支持长按连续输入
        let spaceBtn = createRepeatButton(icon: "space") { [weak self] in
            self?.onSpace?()
        }
        rightStack.addArrangedSubview(spaceBtn)
        
        // 删除按钮 - 支持长按连续删除
        let deleteBtn = createRepeatButton(icon: "delete.left.fill") { [weak self] in
            self?.onDelete?()
        }
        rightStack.addArrangedSubview(deleteBtn)
    }
    
    private func createIconButton(icon: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)), for: .normal)
        btn.tintColor = .secondaryLabel
        // 透明背景，仅图标可见，与系统键盘toolbar风格一致
        btn.backgroundColor = .clear
        btn.addTarget(self, action: action, for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: buttonSize),
            btn.heightAnchor.constraint(equalToConstant: buttonSize),
        ])
        
        return btn
    }
    
    /// 创建支持长按连续操作的按钮
    private func createRepeatButton(icon: String, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)), for: .normal)
        btn.tintColor = .secondaryLabel
        btn.backgroundColor = .clear
        
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: buttonSize),
            btn.heightAnchor.constraint(equalToConstant: buttonSize),
        ])
        
        // 添加长按手势
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.01 // 快速响应
        longPress.allowableMovement = 20
        btn.addGestureRecognizer(longPress)
        
        // 关联action
        objc_setAssociatedObject(btn, &AssociatedKeys.action, action, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        
        // 单次点击
        btn.addTarget(self, action: #selector(repeatButtonTapped(_:)), for: .touchUpInside)
        
        return btn
    }
    
    @objc private func repeatButtonTapped(_ sender: UIButton) {
        // 如果计时器正在运行，说明是长按结束，不执行单次点击
        guard longPressTimer == nil else { return }
        
        if let action = objc_getAssociatedObject(sender, &AssociatedKeys.action) as? () -> Void {
            action()
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let btn = gesture.view as? UIButton,
              let action = objc_getAssociatedObject(btn, &AssociatedKeys.action) as? () -> Void else { return }
        
        switch gesture.state {
        case .began:
            // 立即执行一次
            action()
            
            // 开始计时器
            isInitialDelayPassed = false
            longPressAction = action
            
            // 初始延迟后开始连续操作
            longPressTimer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.isInitialDelayPassed = true
                
                // 切换到更快的重复间隔
                self.longPressTimer?.invalidate()
                self.longPressTimer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { _ in
                    action()
                }
                // 立即执行一次
                action()
            }
            
        case .ended, .cancelled:
            stopLongPressTimer()
            
        default:
            break
        }
    }
    
    private func stopLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressAction = nil
        isInitialDelayPassed = false
    }
    
    deinit {
        stopLongPressTimer()
    }
    
    @objc private func dismissKeyboardTapped() {
        Logger.keyboardInfo("Dismiss keyboard button tapped")
        onDismissKeyboard?()
    }
    
    @objc private func atSymbolTapped() {
        Logger.keyboardInfo("@ symbol button tapped")
        onAtSymbol?()
    }
    
    @objc private func spaceTapped() {
        Logger.keyboardInfo("Space button tapped")
        onSpace?()
    }
    
    @objc private func deleteTapped() {
        Logger.keyboardInfo("Delete button tapped")
        onDelete?()
    }
}

// 用于关联对象的key
private struct AssociatedKeys {
    static var action = "repeatButtonAction"
}
