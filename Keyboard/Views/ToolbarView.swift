import UIKit

final class ToolbarView: UIView {
    var onTranslate: (() -> Void)?
    var onAtSign: (() -> Void)?
    var onSpace: (() -> Void)?
    var onDelete: (() -> Void)?

    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let buttons: [(String, String, Selector)] = [
            ("textformat.abc", "Translate", #selector(translateTapped)),
            ("at", "@", #selector(atTapped)),
            ("space", "Space", #selector(spaceTapped)),
            ("delete.left.fill", "Delete", #selector(deleteTapped)),
        ]

        for (icon, title, action) in buttons {
            let btn = UIButton(type: .system)
            btn.setImage(UIImage(systemName: icon), for: .normal)
            btn.setTitle(" \(title)", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12)
            btn.tintColor = .label
            btn.backgroundColor = .systemGray5
            btn.layer.cornerRadius = 8
            btn.clipsToBounds = true
            btn.addTarget(self, action: action, for: .touchUpInside)
            stackView.addArrangedSubview(btn)
        }
    }

    @objc private func translateTapped() { onTranslate?() }
    @objc private func atTapped() { onAtSign?() }
    @objc private func spaceTapped() { onSpace?() }
    @objc private func deleteTapped() { onDelete?() }
}
