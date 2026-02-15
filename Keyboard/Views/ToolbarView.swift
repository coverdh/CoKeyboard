import UIKit

final class ToolbarView: UIView {
    var onSettings: (() -> Void)?
    var onTranslate: (() -> Void)?
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
        // 左侧菜单按钮
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
        
        // 左上角菜单图标
        let settingsBtn = createIconButton(icon: "line.3.horizontal", action: #selector(settingsTapped))
        leftStack.addArrangedSubview(settingsBtn)
        
        // 右侧功能按钮
        let buttons: [(String, Selector)] = [
            ("textformat.abc", #selector(translateTapped)),
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
        btn.tintColor = .label
        // 使用系统默认配色，兼容iOS 26 玻璃效果
        btn.backgroundColor = .tertiarySystemFill
        btn.layer.cornerRadius = buttonSize / 2
        btn.clipsToBounds = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: buttonSize),
            btn.heightAnchor.constraint(equalToConstant: buttonSize),
        ])
        
        return btn
    }
    
    @objc private func settingsTapped() {
        Logger.keyboardInfo("Settings button tapped")
        onSettings?()
    }
    
    @objc private func translateTapped() {
        Logger.keyboardInfo("Translate button tapped")
        onTranslate?()
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
