import Accelerate
import UIKit

/// What the composer's rainbow shows for a state, the web's composer.css in
/// numbers: the edge's 70% at rest, full with focus, 60% locked, flowing
/// while an answer runs, amber while a change waits; the glow 16% at rest,
/// 30% with focus, 5% locked (8% locked with focus), 14% amber. Amber
/// outranks both flowing and the locked dim glow.
nonisolated struct ComposerLook: Equatable, Sendable {
    enum Edge: Equatable, Sendable {
        case rainbow
        case flowing
        case attention
    }

    let edge: Edge
    private(set) var edgeOpacity: Float
    let glowOpacity: Float

    var glowsAmber: Bool { edge == .attention }

    init(locked: Bool = false, working: Bool = false, waiting: Bool = false, focused: Bool = false) {
        edge = waiting ? .attention : working ? .flowing : .rainbow
        edgeOpacity = focused ? 1 : locked ? 0.6 : 0.7
        if focused {
            glowOpacity = locked ? 0.08 : 0.3
        } else if waiting {
            glowOpacity = 0.14
        } else {
            glowOpacity = locked ? 0.05 : 0.16
        }
    }

    /// The web composer's state as the bridge sends it (`locked`, `working`,
    /// `waiting`), with focus the app's own: the field is first responder,
    /// as the web's `:focus-within`. No state yet draws it at rest.
    init(_ state: ComposerState?, focused: Bool) {
        self.init(locked: state?.locked == true, working: state?.working == true, waiting: state?.waiting == true, focused: focused)
    }

    /// Increase Contrast keeps the edge whole in every state: a dimmed edge
    /// is a fainter line between the box and the page. The web has no such
    /// setting to follow, and the glow, which is only decoration, stays.
    func contrasted(_ high: Bool) -> ComposerLook {
        var look = self
        if high { look.edgeOpacity = 1 }
        return look
    }
}

/// The halo's shape: the composer's box blurred, `.composer::before` since
/// the web's glow became its edge blurred (inset 0, the box's 20 radius,
/// blur(22px)). Only its alpha is drawn here; the colours come from a
/// gradient layer the same as the edge's, so the two match as they move.
///
/// A blur is the one expensive thing here, so it happens once for a width,
/// on a small bitmap (one pixel to the point: it's all soft), and is
/// cached. The image's middle row stretches for a taller box
/// (`contentsCenter`), so new lines, keystrokes and the keyboard never blur
/// anything: they only move a texture. Only a new width (rotation, an iPad's
/// split) draws again, and no state or theme does.
enum ComposerGlow {
    static let radius: CGFloat = RainbowBox.cornerRadius
    static let sigma: CGFloat = 22
    /// How far the halo reaches past the composer's box: three box blurs of
    /// `sigma` reach 3 sigma.
    static let margin: CGFloat = 66
    /// The box height the image is drawn for. Anything taller stretches the
    /// middle row, which the box itself covers, and no composer is shorter.
    static let drawnHeight: CGFloat = 80

    private static var cache: [Int: CGImage] = [:]
    private(set) static var renders = 0

    /// The halo's alpha for a box `width` wide.
    static func mask(width: CGFloat) -> CGImage? {
        let key = Int(width.rounded())
        if let cached = cache[key] { return cached }
        // Only rotation and a resized window bring new widths.
        if cache.count >= 6 { cache.removeAll() }
        let image = render(width: CGFloat(key))
        cache[key] = image
        return image
    }

    private static func render(width: CGFloat) -> CGImage? {
        let size = CGSize(width: width + margin * 2, height: drawnHeight + margin * 2)
        // A layer's mask reads only alpha; the colour channels stay black.
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard width > 0,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)
        else { return nil }

        let body = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
        context.setFillColor(gray: 0, alpha: 1)
        context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        blur(context)
        renders += 1
        return context.makeImage()
    }

    /// Three box blurs make a gaussian of `sigma` (the width the filter
    /// spec gives), with no GPU context to set up.
    private static func blur(_ context: CGContext) {
        guard let pixels = context.data else { return }
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: context.bytesPerRow * context.height, alignment: 16)
        defer { scratch.deallocate() }
        var source = vImage_Buffer(data: pixels, height: vImagePixelCount(context.height), width: vImagePixelCount(context.width), rowBytes: context.bytesPerRow)
        var target = source
        target.data = scratch
        var size = UInt32(sigma * 3 * sqrt(2 * .pi) / 4 + 0.5)
        size |= 1
        for _ in 0..<3 {
            vImageBoxConvolve_ARGB8888(&source, &target, nil, 0, 0, size, size, nil, vImage_Flags(kvImageEdgeExtend))
            swap(&source, &target)
        }
        // An odd number of passes leaves the result in the scratch copy.
        memcpy(pixels, source.data, context.bytesPerRow * context.height)
    }
}

/// The composer's box: the surface, its float shadow, a 2-point rainbow edge
/// and the soft rainbow glow around them, the brand's clearest mark (Live
/// Wire's `.composer` and `.chat-prompt`). The glow is the edge blurred: the
/// same box, the same gradient at the same size and place, and while an
/// answer runs one flow moves both, added together so they share a clock,
/// and the glow beside any point of the edge is that point's colour.
///
/// Everything here is a texture, a gradient or a path the render server
/// already holds: the flow is a Core Animation transform on the two gradient
/// layers, which takes no main-thread work, and the shadow has its path. At
/// rest nothing moves, as on the web, and the flow stops whenever nobody can
/// see it: off the window, or with the window's scene in the background.
final class RainbowBox: UIView {
    static let rainbow: [CGColor] = [0x44FF9A, 0x44B0FF, 0x8B44FF, 0xFF6644, 0xEBFF70].map { UIColor(hexValue: $0).cgColor }
    static let rainbowLocations: [CGFloat] = [0, 0.2341 / 0.9989, 0.4891 / 0.9989, 0.7388 / 0.9989, 1]
    /// `--rainbow`'s first and last stops sit at -0.55% and 99.34% of the box.
    static let rainbowStart: CGFloat = -0.0055
    static let rainbowEnd: CGFloat = 0.9934
    /// `--rainbow-loop`: one loop, its first stop again at its end.
    private static let loop: [UInt32] = [0x44FF9A, 0x44B0FF, 0x8B44FF, 0xFF6644, 0xEBFF70]
    /// `count` loops in a row, for a layer `count` loops (2 box widths each) wide.
    static func loops(_ count: Int) -> [CGColor] {
        (Array(repeating: loop, count: count).flatMap { $0 } + [loop[0]]).map { UIColor(hexValue: $0).cgColor }
    }
    /// The box's corners, which the notice above it shares.
    static let cornerRadius: CGFloat = 20
    private static let flowKey = "flow"
    /// `composer-flow 5s linear infinite`: one loop of `--rainbow-loop`, two box widths, to the right.
    static let flowSeconds: CFTimeInterval = 5
    /// `--duration-base`, eased as the web's `transition: opacity … ease`.
    private static let brighten: CFTimeInterval = 0.22

    private let glow = CALayer()
    private let glowMask = CALayer()
    private let glowColors = CAGradientLayer()
    private let surface = CALayer()
    private let edge = CALayer()
    private let edgeColors = CAGradientLayer()
    private let edgeMask = CAShapeLayer()
    private var laidOutWidth: CGFloat = 0
    /// The window's scene went to the background: nobody sees the flow.
    private var inBackground = false

    var look = ComposerLook() {
        didSet {
            guard look != oldValue else { return }
            if look.edge != oldValue.edge { styleEdge() }
            brighten()
        }
    }

    /// Whether the edge and the glow are moving: while an answer runs and the
    /// box is on screen, unless Reduce Motion is on.
    var isFlowing: Bool { edgeColors.animation(forKey: Self.flowKey) != nil }
    /// Whether the glow is moving with the edge, on the same clock.
    var glowFlowsWithEdge: Bool {
        guard let edgeFlow = edgeColors.animation(forKey: Self.flowKey) as? CABasicAnimation,
              let glowFlow = glowColors.animation(forKey: Self.flowKey) as? CABasicAnimation
        else { return false }
        return edgeFlow.beginTime == glowFlow.beginTime && edgeFlow.duration == glowFlow.duration
            && edgeFlow.toValue as? CGFloat == glowFlow.toValue as? CGFloat
    }
    var glowOpacity: Float { glow.opacity }
    /// The colours the glow is drawn in now, the edge's own.
    var glowGradient: [CGColor] { glowColors.colors as? [CGColor] ?? [] }
    var edgeGradient: [CGColor] { edgeColors.colors as? [CGColor] ?? [] }
    /// Where a point of the box sits in the gradient's colours at the flow's
    /// start, as a fraction of `--rainbow` (a loop of `--rainbow-loop` while
    /// it flows): the same for the edge and the glow.
    func colourPhase(atBoxX x: CGFloat) -> (edge: CGFloat, glow: CGFloat) {
        func phase(_ layer: CAGradientLayer, _ origin: CGFloat) -> CGFloat {
            let local = (x - origin - layer.frame.minX) / layer.frame.width
            let position = (local - layer.startPoint.x) / (layer.endPoint.x - layer.startPoint.x)
            guard look.edge == .flowing else { return position }
            let loops = CGFloat((layer.colors?.count ?? 1) - 1) / CGFloat(Self.loop.count)
            let phase = (position * loops).truncatingRemainder(dividingBy: 1)
            return phase < 0 ? phase + 1 : phase
        }
        return (phase(edgeColors, 0), phase(glowColors, -ComposerGlow.margin))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.shadowOpacity = 1
        layer.shadowOffset = CGSize(width: 0, height: 20)
        layer.shadowRadius = 25

        glowMask.contentsGravity = .resize
        glowMask.contentsScale = 1
        let middle = ComposerGlow.margin + ComposerGlow.drawnHeight / 2
        let rows = ComposerGlow.margin * 2 + ComposerGlow.drawnHeight
        glowMask.contentsCenter = CGRect(x: 0, y: middle / rows, width: 1, height: 1 / rows)
        glow.mask = glowMask
        glow.addSublayer(glowColors)
        surface.cornerRadius = Self.cornerRadius
        surface.cornerCurve = .continuous
        edgeMask.fillColor = UIColor.clear.cgColor
        edgeMask.strokeColor = UIColor.black.cgColor
        edgeMask.lineWidth = 2
        edge.mask = edgeMask
        edge.addSublayer(edgeColors)
        [glow, surface, edge].forEach(layer.addSublayer)
        edge.opacity = look.edgeOpacity
        glow.opacity = look.glowOpacity
        styleColors()

        NotificationCenter.default.addObserver(self, selector: #selector(motionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sceneChanged), name: UIScene.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sceneChanged), name: UIScene.willEnterForegroundNotification, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (box: RainbowBox, _: UITraitCollection) in
            box.styleColors()
            box.brighten(animated: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        without {
            surface.frame = bounds
            edge.frame = bounds
            glow.frame = bounds.insetBy(dx: -ComposerGlow.margin, dy: -ComposerGlow.margin)
            glowMask.frame = glow.bounds
            edgeMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: Self.cornerRadius - 1).cgPath
            // box-shadow's -24px spread is a smaller shape, its 50px blur a radius of half that.
            layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 24, dy: 24), cornerRadius: 0).cgPath
            if bounds.width != laidOutWidth {
                laidOutWidth = bounds.width
                glowMask.contents = ComposerGlow.mask(width: bounds.width)
                styleEdge()
            } else {
                edgeColors.frame.size.height = bounds.height
                glowColors.frame.size.height = glow.bounds.height
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        inBackground = window?.windowScene?.activationState == .background
        updateFlow()
    }

    private func styleColors() {
        without {
            surface.backgroundColor = Palette.surface.resolvedColor(with: traitCollection).cgColor
            layer.shadowColor = Palette.shadow.resolvedColor(with: traitCollection).cgColor
        }
        styleEdge()
    }

    /// Lays the edge's gradient and the glow's over the same box positions:
    /// the glow's layer is the edge's widened by the halo's margin.
    private func styleEdge() {
        without {
            let width = bounds.width
            let margin = ComposerGlow.margin
            let glowBounds = bounds.insetBy(dx: -margin, dy: -margin)
            switch look.edge {
            case .rainbow:
                edgeColors.frame = bounds
                edgeColors.startPoint = CGPoint(x: Self.rainbowStart, y: 0.5)
                edgeColors.endPoint = CGPoint(x: Self.rainbowEnd, y: 0.5)
                glowColors.frame = CGRect(origin: .zero, size: glowBounds.size)
                let glowWidth = max(glowBounds.width, 1)
                glowColors.startPoint = CGPoint(x: (margin + Self.rainbowStart * width) / glowWidth, y: 0.5)
                glowColors.endPoint = CGPoint(x: (margin + Self.rainbowEnd * width) / glowWidth, y: 0.5)
                for colors in [edgeColors, glowColors] {
                    colors.colors = Self.rainbow
                    colors.locations = Self.rainbowLocations.map { NSNumber(value: Double($0)) }
                }
            case .flowing:
                // background-size 200%: a loop is two box widths, and it moves
                // right by one loop. The edge's layer holds two loops from two
                // loops left of the box; the glow's three, from three left of
                // the halo's start, so at any step of the flow both cover what
                // they show and a loop starts at the same box positions in each.
                edgeColors.frame = CGRect(x: -2 * width, y: 0, width: 4 * width, height: bounds.height)
                edgeColors.colors = Self.loops(2)
                glowColors.frame = CGRect(x: margin - 4 * width, y: 0, width: 6 * width, height: glowBounds.height)
                glowColors.colors = Self.loops(3)
                for colors in [edgeColors, glowColors] {
                    colors.startPoint = CGPoint(x: 0, y: 0.5)
                    colors.endPoint = CGPoint(x: 1, y: 0.5)
                    colors.locations = nil
                }
            case .attention:
                let amber = Palette.attention.resolvedColor(with: traitCollection).cgColor
                edgeColors.frame = bounds
                glowColors.frame = CGRect(origin: .zero, size: glowBounds.size)
                for colors in [edgeColors, glowColors] {
                    colors.colors = [amber, amber]
                    colors.locations = nil
                }
            }
        }
        updateFlow(restart: true)
    }

    /// Starts the flow on both gradients in one go, with one begin time, or
    /// stops it: while an answer runs and someone can see the box. Reduce
    /// Motion leaves both on the loop's first frame, as the web's reduced
    /// motion ends the animation at once, both back at the start.
    private func updateFlow(restart: Bool = false) {
        let width = bounds.width
        let wanted = look.edge == .flowing && !UIAccessibility.isReduceMotionEnabled && width > 0
            && window != nil && !inBackground
        if !wanted || restart {
            edgeColors.removeAnimation(forKey: Self.flowKey)
            glowColors.removeAnimation(forKey: Self.flowKey)
        }
        guard wanted, edgeColors.animation(forKey: Self.flowKey) == nil else { return }
        let flow = CABasicAnimation(keyPath: "transform.translation.x")
        flow.fromValue = 0
        flow.toValue = 2 * width
        flow.duration = Self.flowSeconds
        flow.repeatCount = .infinity
        flow.isRemovedOnCompletion = false
        // Siblings share a timeline, so one begin time is one phase.
        flow.beginTime = edgeColors.convertTime(CACurrentMediaTime(), from: nil)
        edgeColors.add(flow, forKey: Self.flowKey)
        glowColors.add(flow, forKey: Self.flowKey)
    }

    /// Focus and locks fade the two lights, in step with the web's transition.
    private func brighten(animated: Bool = true) {
        let shown = look.contrasted(traitCollection.accessibilityContrast == .high)
        CATransaction.begin()
        CATransaction.setAnimationDuration(UIAccessibility.isReduceMotionEnabled || !animated ? 0 : Self.brighten)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .default))
        edge.opacity = shown.edgeOpacity
        glow.opacity = shown.glowOpacity
        CATransaction.commit()
    }

    private func without(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    @objc private func motionChanged() {
        updateFlow(restart: true)
    }

    @objc private func sceneChanged(_ notification: Notification) {
        guard let scene = notification.object as? UIScene, scene === window?.windowScene else { return }
        inBackground = notification.name == UIScene.didEnterBackgroundNotification
        updateFlow()
    }
}
