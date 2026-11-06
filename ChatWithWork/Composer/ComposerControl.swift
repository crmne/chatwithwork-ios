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
        /// `.btn-primary`: send, and stop. Ink square, inverted icon.
        case primary
        /// `.btn-subtle`: send beside stop while an answer runs. The surface,
        /// whose hairline the web's touch bar hides, so an ink icon on the
        /// box's own surface.
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
    /// The icon, apart from UIButton's own image view, which would dim it
    /// again when disabled or highlighted: `colors` alone decides its ink.
    private let icon = UIImageView()
    /// Stop's turning rainbow while the answer runs (`.chat-prompt__ring`).
    private var ring: StopRing?
    /// The pressed globe's inset shadow, inside the target's 1-point edge.
    private let pressedShadow = CAShapeLayer()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        plate.isUserInteractionEnabled = false
        plate.layer.cornerRadius = Self.corner
        plate.layer.cornerCurve = .continuous
        insertSubview(plate, at: 0)
        icon.isUserInteractionEnabled = false
        icon.contentMode = .center
        addSubview(icon)
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
        icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }

    /// One of the web's own Phosphor icons from the asset catalog, at its
    /// 20 points, tinted like a symbol.
    func setIcon(_ name: String) {
        icon.image = UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
    }

    /// The image drawn now, for tests and accessibility snapshots.
    var iconImage: UIImage? { icon.image }

    /// Stop's ring: shown while the answer runs, grey and slow while it
    /// stops (`.chat-prompt__stop:disabled .chat-prompt__ring`).
    var showsRing = false {
        didSet {
            guard showsRing != oldValue else { return }
            if showsRing {
                let ring = StopRing()
                insertSubview(ring, aboveSubview: plate)
                self.ring = ring
                setNeedsLayout()
            } else {
                ring?.removeFromSuperview()
                ring = nil
            }
            restyle()
        }
    }

    var ringView: StopRing? { ring }

    override var isHighlighted: Bool { didSet { restyle() } }
    override var isEnabled: Bool { didSet { restyle() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = (Self.target - Self.side) / 2
        plate.frame = bounds.insetBy(dx: inset, dy: inset)
        sendSubviewToBack(plate)
        icon.frame = bounds
        // The web's ring sits 1px inside the button's 1px edge.
        ring?.frame = bounds.insetBy(dx: 2, dy: 2)

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
            return (isHighlighted ? Palette.surfaceHover : Palette.surface, ink, nil)
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
        // The icon takes it from here, as a UIButton's own image would.
        tintColor = colors.icon
        ring?.stopping = !isEnabled
        // The web's :active nudges a pressed button half a pixel down.
        transform = isHighlighted ? CGAffineTransform(translationX: 0, y: 0.5) : .identity
    }
}

/// `.chat-prompt__ring` on a touch screen: a 2-point ring 40 points across
/// with 13-point corners, a point outside stop's square, where the web's
/// conic rainbow (`--rainbow-conic`) turns once every 2.4 seconds. While the
/// answer stops it's grey at half opacity, turning every 6. It holds still
/// under Reduce Motion.
final class StopRing: UIView {
    static let colors: [UInt32] = [0x44FF9A, 0x44B0FF, 0x8B44FF, 0xFF6644, 0xEBFF70, 0x44FF9A]
    static let thickness: CGFloat = 2
    static let corner: CGFloat = 13
    static let turnKey = "turn"

    private let rainbow = CAGradientLayer()
    private let shape = CAShapeLayer()

    var stopping = false {
        didSet { if stopping != oldValue { style() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        rainbow.type = .conic
        rainbow.startPoint = CGPoint(x: 0.5, y: 0.5)
        rainbow.endPoint = CGPoint(x: 0.5, y: 0)
        layer.addSublayer(rainbow)
        shape.fillRule = .evenOdd
        layer.mask = shape
        style()
        NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // inset: -50%, so the turning square always covers the ring.
        rainbow.frame = bounds.insetBy(dx: -bounds.width / 2, dy: -bounds.height / 2)
        let outer = UIBezierPath(roundedRect: bounds, cornerRadius: Self.corner)
        outer.append(UIBezierPath(roundedRect: bounds.insetBy(dx: Self.thickness, dy: Self.thickness), cornerRadius: Self.corner - Self.thickness))
        shape.frame = bounds
        shape.path = outer.cgPath
        CATransaction.commit()
        turn()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        turn()
    }

    var isTurning: Bool { rainbow.animation(forKey: Self.turnKey) != nil }

    private func style() {
        rainbow.colors = Self.colors.map { value in
            let color = UIColor(hexValue: value)
            guard stopping else { return color.cgColor }
            // filter: grayscale(1)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let grey = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            return UIColor(white: grey, alpha: 1).cgColor
        }
        alpha = stopping ? 0.5 : 1
        rainbow.removeAnimation(forKey: Self.turnKey)
        turn()
    }

    private func turn() {
        guard window != nil, !UIAccessibility.isReduceMotionEnabled, rainbow.animation(forKey: Self.turnKey) == nil else {
            if UIAccessibility.isReduceMotionEnabled { rainbow.removeAnimation(forKey: Self.turnKey) }
            return
        }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = stopping ? 6 : 2.4
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        rainbow.add(spin, forKey: Self.turnKey)
    }

    @objc private func reduceMotionChanged() {
        rainbow.removeAnimation(forKey: Self.turnKey)
        turn()
    }
}
