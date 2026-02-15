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
        
        // 右侧功能按钮：@、空格、删除
        let buttons: [(String, Selector)] = [
            ("at", #selector(atSymbolTapped)),
            ("space", #selector(spaceTapped)),
            ("delete.left.fill", #selector(deleteTapped)),
        ]
        
        for (icon, action) in buttons {
            let btn = createIconButton(icon: icon, action: action)
            rightStack.addArrangedSubview(btn)
        }
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
