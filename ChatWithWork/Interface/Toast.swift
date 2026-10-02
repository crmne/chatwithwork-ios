import UIKit

/// The kinds of notice, as Rails names its flash messages.
enum ToastStyle: Sendable {
    case notice
    case info
    case alert
    case error

    init(type: String?) {
        switch type {
        case "info": self = .info
        case "alert": self = .alert
        case "error": self = .error
        default: self = .notice
        }
    }

    var symbolName: String {
        switch self {
        case .notice: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .alert: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var tint: UIColor {
        switch self {
        case .notice: Palette.positive
        case .info: Palette.live
        case .alert: Palette.attention
        case .error: Palette.negative
        }
    }

    var haptic: Haptics.Feedback? {
        switch self {
        case .notice, .info: nil
        case .alert: .warning
        case .error: .error
        }
    }
}

/// Shows short notices at the top of the screen, above sheets and alerts,
/// in a window of their own that lets every touch outside the notice
/// through. The window only exists while a notice is showing, so it never
/// takes over the status bar.
final class ToastCenter {
    static let shared = ToastCenter()

    private weak var scene: UIWindowScene?
    private var window: PassthroughWindow?
    private weak var current: ToastView?
    private var dismissal: Task<Void, Never>?

    func attach(to scene: UIWindowScene) {
        self.scene = scene
    }

    func show(_ message: String, style: ToastStyle = .notice) {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let container = prepareWindow() else { return }

        if let current { hide(current, animated: true) }

        let toast = ToastView(message: message, style: style)
        toast.onDismiss = { [weak self, weak toast] in
            guard let self, let toast else { return }
            self.hide(toast, animated: true)
        }
        container.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        ])
        current = toast

        container.layoutIfNeeded()
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: -24).scaledBy(x: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
            toast.alpha = 1
            toast.transform = .identity
        }

        if let haptic = style.haptic { Haptics.play(haptic) }
        UIAccessibility.post(notification: .announcement, argument: message)

        dismissal?.cancel()
        let duration = LaunchOptions.toastSeconds ?? Self.duration(for: message)
        dismissal = Task { [weak self, weak toast] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, let toast else { return }
            self.hide(toast, animated: true)
        }
    }

    /// Long enough to read: about 15 characters a second, between 2.5 and 6
    /// seconds.
    static func duration(for message: String) -> Double {
        min(6, max(2.5, Double(message.count) / 15))
    }

    private func prepareWindow() -> UIView? {
        if let window { return window.rootViewController?.view }
        guard let scene else { return nil }

        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false
        self.window = window
        return root.view
    }

    private func hide(_ toast: ToastView, animated: Bool) {
        let finish = { [weak self, weak toast] in
            toast?.removeFromSuperview()
            if let self, self.current == nil || self.current === toast {
                self.window?.isHidden = true
                self.window = nil
            }
        }

        guard animated else { return finish() }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState]) {
            toast.alpha = 0
            toast.transform = CGAffineTransform(translationX: 0, y: -16)
        } completion: { _ in
            finish()
        }
    }
}

/// A window that only catches touches on its own subviews.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === rootViewController?.view ? nil : view
    }
}

/// One notice: an icon in the notice's color and its text, on glass.
private final class ToastView: UIView {
    var onDismiss: (() -> Void)?

    init(message: String, style: ToastStyle) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let background: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            background = UIVisualEffectView(effect: glass)
            background.cornerConfiguration = .capsule(maximumRadius: 26)
        } else {
            background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
            background.layer.cornerRadius = 22
            background.layer.cornerCurve = .continuous
            background.clipsToBounds = true
            background.layer.borderWidth = 1 / UIScreen.main.scale
            background.layer.borderColor = Palette.line.cgColor
        }
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let icon = UIImageView(image: UIImage(systemName: style.symbolName))
        icon.tintColor = style.tint
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .large)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = message
        label.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.ink
        label.numberOfLines = 4

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -18),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

        isAccessibilityElement = true
        accessibilityLabel = message
        accessibilityTraits = .staticText
        accessibilityIdentifier = "toast"

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismiss))
        swipe.direction = .up
        addGestureRecognizer(swipe)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func dismiss() {
        onDismiss?()
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
