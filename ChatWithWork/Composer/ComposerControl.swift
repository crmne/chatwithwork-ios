import UIKit

/// A button in the composer's bar, drawn as the web draws its composer's
/// buttons on a touch screen (`.chat-prompt__bar .btn-square`, Chat with
/// Work's `components/composer.css` and `buttons.css`): a 44-point target
/// painting a 34-point square (inside the button's 1px edge and 4px
/// padding) with 9-point corners, and a 20-point icon. No circles, no
/// outlines at rest.
final class ComposerControl: UIButton {
    enum Style: Equatable {
        /// `.btn-ghost`: attach, dictate, cancel. Ink on nothing.
        case ghost
        /// The globe (`.chat-prompt__web-search-toggle`): muted off, ink on a
        /// pressed 10% ink square when on, faint where it can't search. Its
        /// square's corners are 5 points (the toggle's own 10px radius,
        /// inside the edge and padding), and on, the web's inset shadow
        /// (0 1px 2px, ink at 12%) falls round the target's inner edge.
        case toggle
        /// `.btn-primary`: send, and stop on its own. Ink square, inverted icon.
        case primary
        /// `.btn-subtle`: stop beside send. Surface with a strong hairline.
        case subtle
    }

    static let target: CGFloat = 44
    static let side: CGFloat = 34
    static let corner: CGFloat = 9
    static let toggleCorner: CGFloat = 5
    /// The web's icon boxes are 20px (stop's 15px); SF Symbols at these
    /// sizes draw glyphs of the same height as its Phosphor icons.
    static let iconPointSize: CGFloat = 19
    static let stopPointSize: CGFloat = 13

    var style: Style { didSet { restyle() } }
    /// The globe's `aria-pressed`.
    var isOn = false { didSet { restyle() } }
    /// The globe's `aria-disabled`: tappable, to say why, but faint.
    var isInert = false { didSet { restyle() } }

    private let plate = UIView()
    /// The pressed globe's inset shadow, inside the target's 1-point edge.
    private let pressedShadow = CAShapeLayer()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        plate.isUserInteractionEnabled = false
        plate.layer.cornerRadius = Self.corner
        plate.layer.cornerCurve = .continuous
        insertSubview(plate, at: 0)
        // Only the shadow shows, cast inward by the ring round the edge.
        pressedShadow.fillColor = nil
        pressedShadow.shadowOffset = CGSize(width: 0, height: 1)
        pressedShadow.shadowRadius = 1
        pressedShadow.shadowOpacity = 0.12
        pressedShadow.isHidden = true
        layer.insertSublayer(pressedShadow, at: 0)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.target),
            heightAnchor.constraint(equalToConstant: Self.target)
        ])
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (control: ComposerControl, _: UITraitCollection) in
            control.restyle()
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ name: String, pointSize: CGFloat = ComposerControl.iconPointSize, weight: UIImage.SymbolWeight = .medium) {
        setImage(UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)), for: .normal)
    }

    /// One of the web's own Phosphor icons from the asset catalog, at its
    /// 20 points, tinted like a symbol.
    func setIcon(_ name: String) {
        setImage(UIImage(named: name)?.withRenderingMode(.alwaysTemplate), for: .normal)
    }

    override var isHighlighted: Bool { didSet { restyle() } }
    override var isEnabled: Bool { didSet { restyle() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = (Self.target - Self.side) / 2
        plate.frame = bounds.insetBy(dx: inset, dy: inset)
        sendSubviewToBack(plate)

        let edge = bounds.insetBy(dx: 1, dy: 1)
        let inner = UIBezierPath(roundedRect: CGRect(origin: .zero, size: edge.size), cornerRadius: Self.corner)
        let outer = UIBezierPath(rect: CGRect(origin: .zero, size: edge.size).insetBy(dx: -8, dy: -8))
        // Reversed, so the hole stays a hole in the shadow path too, which
        // takes no fill rule.
        outer.append(inner.reversing())
        pressedShadow.frame = edge
        pressedShadow.path = outer.cgPath
        pressedShadow.shadowPath = outer.cgPath
        let mask = CAShapeLayer()
        mask.path = inner.cgPath
        pressedShadow.mask = mask
    }

    /// What the plate and icon show now. `alpha` stays the view's own, so
    /// hiding and showing it elsewhere keeps working.
    var colors: (plate: UIColor, icon: UIColor, edge: UIColor?) {
        let ink = Palette.ink
        switch style {
        case .ghost:
            if !isEnabled { return (.clear, ink.withAlphaComponent(0.2), nil) }
            return (isHighlighted ? ink.withAlphaComponent(0.07) : .clear, ink, nil)
        case .toggle:
            if isInert { return (.clear, Palette.inkFaint, nil) }
            if isOn { return (ink.withAlphaComponent(0.1), ink, nil) }
            return (isHighlighted ? ink.withAlphaComponent(0.07) : .clear, isHighlighted ? ink : Palette.inkMuted, nil)
        case .primary:
            // daisyUI's disabled button, at the half opacity the web's send has then.
            if !isEnabled { return (ink.withAlphaComponent(0.05), ink.withAlphaComponent(0.1), nil) }
            return (isHighlighted ? ink.withAlphaComponent(0.84) : ink, Palette.inkInverted, nil)
        case .subtle:
            if !isEnabled { return (ink.withAlphaComponent(0.05), ink.withAlphaComponent(0.1), nil) }
            return (isHighlighted ? Palette.surfaceHover : Palette.surface, ink, Palette.lineStrong)
        }
    }

    private func restyle() {
        let colors = colors
        plate.backgroundColor = colors.plate
        plate.layer.cornerRadius = style == .toggle ? Self.toggleCorner : Self.corner
        pressedShadow.isHidden = !(style == .toggle && isOn && !isInert)
        pressedShadow.shadowColor = Palette.ink.resolvedColor(with: traitCollection).cgColor
        plate.layer.borderWidth = colors.edge == nil ? 0 : 1
        plate.layer.borderColor = colors.edge?.resolvedColor(with: traitCollection).cgColor
        tintColor = colors.icon
        // The web's :active nudges a pressed button half a pixel down.
        transform = isHighlighted ? CGAffineTransform(translationX: 0, y: 0.5) : .identity
    }
}
