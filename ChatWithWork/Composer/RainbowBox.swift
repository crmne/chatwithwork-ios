import Accelerate
import UIKit

/// What the composer's rainbow shows for a state, the web's composer.css in
/// numbers: the edge's 70% at rest, full with focus, flowing while an answer
/// runs, amber while a change waits, and the glow 14% at rest, 30% with
/// focus, 5% locked. Amber outranks both flowing and the locked dim.
nonisolated struct ComposerLook: Equatable, Sendable {
    enum Edge: Equatable, Sendable {
        case rainbow
        case flowing
        case attention
    }

    let edge: Edge
    let edgeOpacity: Float
    let glowOpacity: Float

    var glowsAmber: Bool { edge == .attention }

    init(locked: Bool = false, working: Bool = false, waiting: Bool = false, focused: Bool = false) {
        edge = waiting ? .attention : working ? .flowing : .rainbow
        edgeOpacity = focused ? 1 : locked ? 0.6 : 0.7
        if focused {
            glowOpacity = locked ? 0.08 : 0.3
        } else {
            glowOpacity = locked && !waiting ? 0.05 : 0.14
        }
    }
}

/// The blurred halo behind the composer, `.rainbow-glow` with `.composer`'s
/// sizes: its box 0.4rem past the composer's, a 28 radius, blur(20px).
///
/// A blur is the one expensive thing here, so it happens once for a width,
/// on a small bitmap (one pixel to the point: it's all soft), and is cached.
/// The image's middle row stretches for a taller box (`contentsCenter`), so
/// new lines, keystrokes and the keyboard never blur anything: they only
/// move a texture. Only a new width (rotation, an iPad's split) draws again.
enum ComposerGlow {
    static let outset: CGFloat = 6.4
    static let radius: CGFloat = 28
    static let sigma: CGFloat = 20
    /// How far the halo reaches past the composer's box.
    static let margin: CGFloat = 67
    /// The box height the image is drawn for. Anything taller stretches the
    /// middle row, which the box itself covers, and no composer is shorter.
    static let drawnHeight: CGFloat = 80

    private struct Key: Hashable {
        let width: Int
        let amber: Bool
        let dark: Bool
    }

    private static var cache: [Key: CGImage] = [:]
    private(set) static var renders = 0

    /// The halo for a box `width` wide: the rainbow, or amber (`attention`).
    static func image(width: CGFloat, attention: CGColor?, dark: Bool) -> CGImage? {
        let key = Key(width: Int(width.rounded()), amber: attention != nil, dark: dark && attention != nil)
        if let cached = cache[key] { return cached }
        // Only rotation and a resized window bring new widths.
        if cache.count >= 6 { cache.removeAll() }
        let colors = attention.map { [$0, $0] } ?? RainbowBox.rainbow
        let image = render(width: CGFloat(key.width), colors: colors, locations: attention == nil ? RainbowBox.rainbowLocations : [0, 1])
        cache[key] = image
        return image
    }

    private static func render(width: CGFloat, colors: [CGColor], locations: [CGFloat]) -> CGImage? {
        let size = CGSize(width: width + margin * 2, height: drawnHeight + margin * 2)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard size.width > margin * 2,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info),
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)
        else { return nil }

        let body = CGRect(origin: .zero, size: size).insetBy(dx: margin - outset, dy: margin - outset)
        context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.minX - 0.0055 * body.width, y: 0),
            end: CGPoint(x: body.minX + 0.9934 * body.width, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
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
/// Wire's `.composer` and `.chat-prompt`). Everything here is a texture or a
/// path the render server already holds: the edge's flow is a Core Animation
/// transform, which takes no main-thread work, and the shadow has its path.
final class RainbowBox: UIView {
    static let rainbow: [CGColor] = [0x44FF9A, 0x44B0FF, 0x8B44FF, 0xFF6644, 0xEBFF70].map { UIColor(hexValue: $0).cgColor }
    static let rainbowLocations: [CGFloat] = [0, 0.2341 / 0.9989, 0.4891 / 0.9989, 0.7388 / 0.9989, 1]
    /// `--rainbow-loop`, twice over: the flow slides it one whole loop.
    private static let rainbowLoop: [CGColor] = [0x44FF9A, 0x44B0FF, 0x8B44FF, 0xFF6644, 0xEBFF70, 0x44FF9A, 0x44B0FF, 0x8B44FF, 0xFF6644, 0xEBFF70, 0x44FF9A]
        .map { UIColor(hexValue: $0).cgColor }
    /// The box's corners, which the notice above it shares.
    static let cornerRadius: CGFloat = 20
    private static let flowKey = "flow"
    private static let flowSeconds: CFTimeInterval = 5
    /// `--duration-base`.
    private static let brighten: CFTimeInterval = 0.22

    private let glow = CALayer()
    private let surface = CALayer()
    private let edge = CALayer()
    private let edgeColors = CAGradientLayer()
    private let edgeMask = CAShapeLayer()
    private var laidOutWidth: CGFloat = 0

    var look = ComposerLook() {
        didSet {
            guard look != oldValue else { return }
            if look.edge != oldValue.edge { styleEdge() }
            brighten()
        }
    }

    /// Whether the edge is moving: while an answer runs, unless Reduce Motion is on.
    var isFlowing: Bool { edgeColors.animation(forKey: Self.flowKey) != nil }
    var glowOpacity: Float { glow.opacity }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.shadowOpacity = 1
        layer.shadowOffset = CGSize(width: 0, height: 20)
        layer.shadowRadius = 25

        glow.contentsGravity = .resize
        glow.contentsScale = 1
        let middle = ComposerGlow.margin + ComposerGlow.drawnHeight / 2
        let rows = ComposerGlow.margin * 2 + ComposerGlow.drawnHeight
        glow.contentsCenter = CGRect(x: 0, y: middle / rows, width: 1, height: 1 / rows)
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

        NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        without {
            surface.frame = bounds
            edge.frame = bounds
            glow.frame = bounds.insetBy(dx: -ComposerGlow.margin, dy: -ComposerGlow.margin)
            edgeMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: Self.cornerRadius - 1).cgPath
            // box-shadow's -24px spread is a smaller shape, its 50px blur a radius of half that.
            layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 24, dy: 24), cornerRadius: 0).cgPath
            if bounds.width != laidOutWidth {
                laidOutWidth = bounds.width
                styleEdge()
            } else {
                edgeColors.frame.size.height = bounds.height
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        styleColors()
    }

    private func styleColors() {
        without {
            surface.backgroundColor = Palette.surface.resolvedColor(with: traitCollection).cgColor
            layer.shadowColor = Palette.shadow.resolvedColor(with: traitCollection).cgColor
        }
        styleEdge()
    }

    private func styleEdge() {
        without {
            let width = bounds.width
            edgeColors.removeAnimation(forKey: Self.flowKey)
            switch look.edge {
            case .rainbow:
                edgeColors.frame = bounds
                edgeColors.startPoint = CGPoint(x: -0.0055, y: 0.5)
                edgeColors.endPoint = CGPoint(x: 0.9934, y: 0.5)
                edgeColors.colors = Self.rainbow
                edgeColors.locations = Self.rainbowLocations.map { NSNumber(value: Double($0)) }
            case .flowing:
                // background-size 200%: a loop is two box widths, and it moves right by one.
                edgeColors.frame = CGRect(x: -2 * width, y: 0, width: 4 * width, height: bounds.height)
                edgeColors.startPoint = CGPoint(x: 0, y: 0.5)
                edgeColors.endPoint = CGPoint(x: 1, y: 0.5)
                edgeColors.colors = Self.rainbowLoop
                edgeColors.locations = nil
                if !UIAccessibility.isReduceMotionEnabled, width > 0 {
                    let flow = CABasicAnimation(keyPath: "transform.translation.x")
                    flow.fromValue = 0
                    flow.toValue = 2 * width
                    flow.duration = Self.flowSeconds
                    flow.repeatCount = .infinity
                    flow.isRemovedOnCompletion = false
                    edgeColors.add(flow, forKey: Self.flowKey)
                }
            case .attention:
                let amber = Palette.attention.resolvedColor(with: traitCollection).cgColor
                edgeColors.frame = bounds
                edgeColors.colors = [amber, amber]
                edgeColors.locations = nil
            }
            let amber = look.glowsAmber ? Palette.attention.resolvedColor(with: traitCollection).cgColor : nil
            glow.contents = ComposerGlow.image(width: width, attention: amber, dark: traitCollection.userInterfaceStyle == .dark)
        }
    }

    /// Focus and locks fade the two lights, in step with the web's transition.
    private func brighten() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(UIAccessibility.isReduceMotionEnabled ? 0 : Self.brighten)
        edge.opacity = look.edgeOpacity
        glow.opacity = look.glowOpacity
        CATransaction.commit()
    }

    private func without(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    @objc private func reduceMotionChanged() {
        styleEdge()
    }
}
